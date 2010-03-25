require 'rubygems'
require 'bundler'
Bundler.setup

require 'sinatra/base'
require 'sinatra/async'
require 'haml'
require 'sass'
require 'yajl'

require 'mongo'
CONN = Mongo::Connection.new
DB = CONN.db('memprof_site')

require 'memprof.com'

class MemprofApp < Sinatra::Base
  register Sinatra::Async

  apost '/upload' do
    upload = params["upload"]
    name   = params["name"]
    key    = params["key"]

    user = begin
      DB.collection('users').find_one(:_id => Mongo::ObjectID.from_string(key))
    rescue Mongo::InvalidObjectID
      nil
    end

    unless user
      body "Bad API key."
      return
    end
    unless upload && tempfile = upload[:tempfile]
      body "Failed - no file."
      return
    end
    unless name && !name.empty?
      body "Failed - no dump name."
      return
    end
    # Slight deterrent to people uploading bullshit files?
    unless upload[:type] == "application/x-gzip"
      body "Failed."
      return
    end

    # we need the dump id to use it as the collection name for the dump import.
    # we'll delete it if the import fails for some reason.
    dump_id = DB.collection('dumps').insert(
      :name => name,
      :user_id => user['_id'],
      :created_at => Time.now
    )

    basename = "dumps/#{dump_id.to_s}"

    tempfile.close
    File.rename(tempfile.path, "#{basename}.json.gz")

    EM.system("gunzip -f #{basename}.json.gz") {|o1, s1|
      if s1.exitstatus == 0
        EM.system("ruby import_json.rb #{basename}.json") {|o2, s2|
          if s2.exitstatus == 0
            (user['dumps'] ||= []) << dump_id
            DB.collection('users').save(user)
            body "Success! Visit http://www.memprof.com/dump/#{dump_id.to_s} to view."
          else
            # make sure we remove the dump if it failed
            DB.collection('dumps').remove(:_id => dump_id)
            body "Failed to import your file!"
          end
          File.delete("#{basename}.json") if File.exist?("#{basename}.json")
          File.delete("#{basename}_refs.json") if File.exist?("#{basename}_refs.json")
        }
      else
        # make sure we remove the dump if it failed
        DB.collection('dumps').remove(:_id => dump_id)
        File.delete("#{basename}.json.gz") if File.exist?("#{basename}.json.gz")
        body "Failed to decompress your file!"
      end
    }
  end

  get '/dump/:dump/?:view?' do
    @dump = Memprof::Dump.new(params[:dump])
    @db = @dump.db
    pass unless @db.count > 0

    render_panel(params[:view])
  end

  get %r'/(demo|panel)?$' do
    redirect '/dump/stdlib'
  end

  get '/signup' do
    haml :main
  end

  post '/email' do
    DB.collection('emails').insert(
      :email => params[:email_addr],
      :time => Time.now,
      :ip => request.ip
    )
    haml :thanks
  end

  get '/beta' do
    session[:beta] = true
    redirect '/'
  end

  get '/logout' do
    session.delete(:beta)
    redirect '/'
  end

  get '/app.css' do
    content_type('text/css')
    sass :app
  end

  helpers do
    def url_for(subview, where=nil, of=nil)
      url = "/dump/#{@dump.name}/#{subview}"
      if where or of
        url += "?"
        url += "where=#{Yajl.dump where}" if where
        url += "of=#{Yajl.dump of}" if of
      end
      url
    end
    def render_panel(subview=nil)
      where = (params[:where] && !params[:where].empty? ? Yajl.load(params[:where]) : nil)
      where.delete("$where") if where

      of = (params[:of] && !params[:of].empty? ? Yajl.load(params[:of]) : nil)
      of.delete("$where") if of

      content = case subview
      when 'subclasses'
        render_subclasses(where, of)
      when /^group:?(.*)$/
        subview = 'group'
        render_group(where || of, $1.empty? ? nil : $1)
      when 'detail'
        render_detail(where)
      when 'references'
        render_references(where, of)
      else
        subview = 'namespace'
        render_namespace(where || of)
      end

      @where, @of = where, of

      if of
        content
      else
        partial :_panel,
          :layout => request.xhr? ? false : :newui,
          :content => content,
          :subview => subview
      end
    end
    def render_namespace(where=nil)
      if where
        obj = @db.find_one(where)
      else
        obj = @dump.root_object
      end

      constants = obj['ivars'].reject{ |k,v| k !~ /^[A-Z]/ }
      names = constants.invert

      classes = @db.find(
        :type => {:$in => %w[iclass class module]},
        :_id  => {:$in => constants.values}
      ).to_a.sort_by{ |o| names[o['_id']] || o['name'] }

      classes.each do |o|
        unless o['name'] == 'Object'
          vars = o['ivars'].reject{ |k,v| k !~ /^[A-Z]/ }
          o['hasChildren'] = !!@db.find_one(
            :type => {:$in => %w[iclass class module]},
            :_id  => {:$in => vars.values}
          )
        end
      end

      partial :_namespace,
        :list => classes,
        :names => names
    end
    def render_subclasses(where=nil,of=nil)
      if of
        klass = @db.find_one(of)
        subclasses = @dump.subclasses_of(klass).sort_by{ |o| o['name'] || '' }
      elsif where
        subclasses = [@db.find_one(where)]
      else
        subclasses = [@dump.root_object]
      end

      subclasses.compact!
      subclasses.each do |o|
        o['hasSubclasses'] = @dump.subclasses_of?(o)
      end

      partial :_subclasses,
        :list => subclasses
    end
    def render_references(where=nil,of=nil)
      if where
        list = [@db.find_one(where)]
      elsif of
        list = @dump.refs.find(of).limit(25)
      else
        list = []
      end

      if list.count == 0
        return '<center>no references found</center>'
      else
        partial :_references,
          :list => list
      end
    end
    def render_group(where=nil,key=nil)
      if where
         key ||= possible_groupings_for(where).first
      else
        key ||= 'file'
        where = nil
      end

      if key.nil?
        return '<center>no possible groupings</center>'
      end

      @group_key = key

      if key == 'age'
        min = @db.find(:time => {:$exists => true}).sort([:time, :asc ]).limit(1).first['time']
        max = @db.find(:time => {:$exists => true}).sort([:time, :desc]).limit(1).first['time']
        time_range = [min, max]

        start = 50_000
        curr = max
        time_slices = []

        while curr > min
          time_slices << curr
          curr -= start
          start *= 2
        end
        time_slices << min

        result = @db.map_reduce(
          'function(){ for (var i=0; i<time_slices.length; i++) { if (this.time >= time_slices[i]) { emit(time_slices[i], 1); break; } } }',
          'function(k,vals){ var n=0; for(var i=0; i<vals.length; i++) n+=vals[i]; return n }',
          :scope => {:time_slices => time_slices},
          :query => where.merge(:time => {:$exists => true}),
          :verbose => true
        )

        slices = []
        key = 'time'
        list = result.find.sort_by{ |o| -o['_id'] }.map{ |o| o['_id'] = o['_id'].to_i; slices << o['_id']; o }
        list.map! do |o|
          a = o['_id']
          w = {'$gte' => a}
          if n = slices.select{ |t| t > a }.last
            w['$lt'] = n
          end
          {'count' => o['value'], 'time' => w}
        end

        result.drop
      else
        list = @db.group(
          [key],
          where,
          {:count=>0},
          'function(d,o){ o.count++ }'
        ).sort_by{ |o| -o['count'] }.first(100)
      end

      partial :_group,
        :list => list,
        :key => key,
        :where => where,
        :time_range => time_range
    end
    def render_detail(where=nil)
      if where
        list = @db.find(where).limit(200)
      else
        list = [@dump.root_object]
      end

      if list.count == 0
        return '<center>no matching objects</center>'
      elsif list.count == 1
        partial :_detail,
          :obj => list.first
      else
        partial :_list,
          :list => list
      end
    end
    def possible_groupings_for(w)
      possible = %w[ type file ]

      case w['type']
      when 'string', 'hash', 'array', 'regexp', 'bignum'
        possible << 'line' if w.has_key?('file')
        possible << 'length'
        possible << 'data' if %w[ string regexp ].include?(w['type'])
      when 'module', 'class'
        possible << 'name'
      when 'data', 'object'
        possible << 'class_name'
      when 'node'
        possible << 'node_type'
      end

      possible << 'line' if w.has_key?('file')
      possible << 'age' unless w.has_key?('time')

      possible -= w.keys
      possible -= %w[type] if w.has_key?('class_name')
      possible.uniq!
      possible
    end
    def json obj
      content_type('application/json')
      body(Yajl.dump obj)
      throw :halt
    end
    def partial name, locals = {}
      haml name, :layout => locals.delete(:layout) || false, :locals => locals
    end
    def show_addr val
      if val =~ /^0x/
        "<a href='#{url_for 'detail', :_id => val}'>#{val}</a>"
      else
        '&nbsp;'
      end
    end
    def show_val val, as_link = true
      case val
      when nil
        'nil'
      when OrderedHash, /^0x/, 'globals'
        if val.is_a?(OrderedHash)
          obj = val
        else
          obj = @db.find_one(:_id => val)
        end

        return val unless obj

        show = case obj['type']
        when 'class', 'module', 'iclass'
          if name = obj['name']
            "#{name}"
          elsif obj['ivars'] and attached = obj['ivars']['__attached__']
            "#<MetaClass:#{show_val attached, false}>"
          else
            "#<#{obj['type'] == 'class' ? 'Class' : 'Module'}:#{obj['_id']}>"
          end
        when 'regexp'
          "/#{obj['data']}/"
        when 'string'
          if str = obj['data']
            str.dump
          elsif parent = obj['shared']
            o = @db.find_one(:_id => parent)
            o['data'].dump
          end
        when 'bignum'
          "#<Bignum length=#{obj['length']}>"
        when 'match'
          "#<Match:#{obj['_id']}>"
        when 'float'
          num = obj['data']
          "#<Float value=#{num}>"
        when 'hash', 'array'
          "#<#{obj['type'] == 'hash' ? 'Hash' : 'Array'}:#{obj['_id']} length=#{obj['length']}>"
        when 'data', 'object'
          if node = obj['nd_body'] and node = @db.find_one(:_id => node) and node['file']
            suffix = " #{node['file'].split('/').last(4).join('/')}:#{node['line']}"
          end
          "#<#{obj['class_name'] || 'Object'}:#{obj['_id']}#{suffix}>"
        when 'node'
          nd_type = obj['node_type']
          if nd_type == 'CFUNC' and obj['n1'] =~ /: (\w+)/
            name = $1
            suffix = " (#{name})" unless name =~ /dylib_header/
          elsif nd_type == 'CREF'
            name = show_val(obj.nd_clss, false)
            suffix = " (#{name})" if name
          elsif nd_type == 'CONST'
            suffix = " (#{obj.n1[1..-1]})" if obj.n1
          end
          "node:#{nd_type}#{suffix}"
        when 'varmap'
          vars = obj['data']
          vars = obj['data'].keys if vars
          "#<Varmap:#{obj['_id']}#{vars ? " var=#{vars.join(', ')}" : nil}>"
        when 'scope'
          vars = obj['variables']
          vars = obj['variables'].keys - ['_','~'] if vars
          vars = nil unless vars and vars.any?
          "#<Scope:#{obj['_id']}#{vars ? " variables=#{vars.join(', ')}" : nil}>"
        when 'frame'
          klass = show_val(obj['last_class'], false) if obj['last_class']
          func = obj['last_func'] || obj['orig_func']
          func = func ? func[1..-1] : '(unknown)'

          suffix = " #{klass ? klass + "#" : nil}#{func}" if klass or func
          "Frame:#{obj['_id']}#{suffix}"
        when 'file'
          "#<File:#{obj['_id']}>"
        when 'struct'
          "#<#{obj['class_name'] || 'Struct'}:#{obj['_id']}>"
        else
          obj['_id']
        end

        if as_link
          "<a href='#{url_for 'detail', :_id => obj['_id']}'>#{h show}</a>"
        else
          show
        end
      else
        val
      end
    end

    include Rack::Utils
    alias_method :h, :escape_html
  end

  set :server, 'thin'
  set :port, 7006
  set :public, File.expand_path('../public', __FILE__)
  enable :static, :logging
  use Rack::Session::Cookie, :key => 'memprof_session', :secret => 'noisses_forpmem'
end

if __FILE__ == $0
  MemprofApp.run!
end
