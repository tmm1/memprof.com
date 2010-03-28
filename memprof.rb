require 'rubygems'
require 'bundler'
Bundler.setup

require 'sinatra/base'
require 'sinatra/async'
require 'haml'
require 'sass'
require 'yajl'
require 'bcrypt'
require 'securerandom'

require 'db'

require 'memprof.com'

class MemprofApp < Sinatra::Base
  register Sinatra::Async

  apost '/upload' do
    upload = params["upload"]
    name   = params["name"]
    key    = params["key"]

    user = DB.collection('users').find_one(:api_key => key)

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

    basename = File.expand_path("../dumps/#{dump_id.to_s}", __FILE__)

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
          File.delete("#{basename}.json") if File.exists?("#{basename}.json")
          File.delete("#{basename}_refs.json") if File.exists?("#{basename}_refs.json")
        }
      else
        # make sure we remove the dump if it failed
        DB.collection('dumps').remove(:_id => dump_id)
        File.delete("#{basename}.json.gz") if File.exist?("#{basename}.json.gz")
        body "Failed to decompress your file!"
      end
    }
  end

  get %r'/(demo|panel)?$' do
    haml :_home, :layout => :newui
  end

  get '/howto' do
    partial :_howto
  end

  get '/pricing' do
    partial :_pricing
  end

  get '/contact' do
    partial :_contact
  end

  get '/faq' do
    partial :_faq
  end

  get '/signup' do
    partial :_signup
  end

  post '/signup' do
    unless params[:username].any?
      throw(:halt, [500, "You need a username, bro."])
    end
    unless params[:name].any?
      throw(:halt, [500, "You need a name, bro."])
    end
    unless params[:email].any? && params[:email].include?("@")
      throw(:halt, [500, "You need valid email, bro."])
    end
    unless params[:password].length > 5
      throw(:halt, [500, "Password must be longer than 5 characters."])
    end
    unless params[:password] == params[:password_confirmation]
      throw(:halt, [500, "Password does not match the confirmation."])
    end
    if user = DB.collection('users').find_one(:email => params[:email])
      throw(:halt, [500, "Someone is already signed up with that email, bro."])
    end
    if user = DB.collection('users').find_one(:username => params[:username])
      throw(:halt, [500, "Someone is already signed up with that username, bro."])
    end

    DB.collection('users').insert({
      :username   => params[:username],
      :name       => params[:name],
      :email      => params[:email],
      :password   => BCrypt::Password.create(params[:password]).to_s,
      :created_at => Time.now,
      :ip         => request.ip,
      :dumps      => [],
      :api_key    => SecureRandom.hex(8)
    })
    "Signup successful! Please login to proceed."
  end

  get '/login' do
    partial :_login
  end

  post '/login' do
    user = DB.collection('users').find_one(:email => params[:login]) || DB.collection('users').find_one(:username => params[:login])

    unless user
      throw(:halt, [500, "Invalid login."])
    end

    db_pass = BCrypt::Password.new(user['password'])

    # BCrypt::Password defines == to do its special decryption
    # or whatever, so it must be the left 'operand'
    unless db_pass == params[:password]
      throw(:halt, [500, "Invalid password."])
    end

    session[:user_id] = user['_id'].to_s
    "Logged in successfully!"
  end

  get '/logout' do
    session.delete(:user_id)
    redirect '/'
  end

  get '/app.css' do
    content_type('text/css')
    sass :app
  end

  get '/dump/:dump/?:view?' do
    @dump = Memprof::Dump.new(params[:dump])
    @db = @dump.db
    pass unless @db.count > 0

    @dump_metadata = DUMPS.find_one(:_id => (ObjectID(params[:dump]) rescue params[:dump]))
    @dump_user     = USERS.find_one(:_id => @dump_metadata['user_id'])

    session[:dump] = params[:dump]
    render_panel(params[:view])
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
      where['_id'] = ObjectID(where.delete('_id')['$oid']) if where and where['_id'].is_a?(Hash) and where['_id'].has_key?('$oid')

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
      when 'namespace'
        render_namespace(where || of)
      else
        subview = 'summary'
        return partial(:_summary, :layout => request.xhr? ? false : :newui)
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
          :query => (where || {}).merge(:time => {:$exists => true}),
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
      when OrderedHash, /^0x/, 'globals', /^lsof/
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
          "#<#{obj['class_name'] || 'Bignum'} length=#{obj['length']}>"
        when 'match'
          "#<#{obj['class_name'] || 'MatchData'}:#{obj['_id']}>"
        when 'float'
          num = obj['data']
          "#<#{obj['class_name'] || 'Float'} value=#{num}>"
        when 'hash', 'array'
          "#<#{obj['class_name'] || (obj['type'] == 'hash' ? 'Hash' : 'Array')}:#{obj['_id']} length=#{obj['length']}>"
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
          elsif nd_type == 'BLOCK' or nd_type == 'NEWLINE'
            suffix = " (#{obj['file'].split('/').last(2).join('/')}:#{obj['line']})"
          elsif nd_type == 'METHOD'
            klass = @dump.refs.find_one(:refs => obj['_id'])
            klass = @dump.db.find_one(:_id => klass['_id']) if klass
            name = klass['methods'].find{ |k,v| v == obj['_id'] }.first
            suffix = " (#{name})" if name
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
          if func = obj['last_func'] || obj['orig_func']
            func = func[1..-1]
            "#{klass ? klass + "#" : nil}#{func}".gsub(/#<MetaClass:(.+?)>#(.+)$/){ "#{$1}.#{$2}" }
          else
            "#<Frame:#{obj['_id']}>"
          end
        when 'file'
          "#<#{obj['class_name'] || 'File'}:#{obj['_id']}>"
        when 'struct'
          "#<#{obj['class_name'] || 'Struct'}:#{obj['_id']}>"
        when 'lsof'
          name = obj['fd_name']
          name = name.split('/').last(3).join('/') if name =~ /^\//
          name = name.gsub('->', ' -> ')
          "(#{obj['fd_type']}:#{obj['fd']}) #{name}"
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
    def get_dumps()
      dumps = DB.collection('dumps').find.sort([:created_at, :desc]).to_a
      users = Hash[ *DB.collection('users').find.map{ |u| [u['_id'], u] }.flatten(1) ]
      dumps.each{ |d| d['user'] = users[d['user_id']] }
      dumps
    end
    def logged_in?
      session[:user_id]
    end
    def current_user
      logged_in? && DB.collection('users').find_one(:_id => Mongo::ObjectID.from_string(session[:user_id])) rescue nil
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
