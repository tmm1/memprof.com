require 'rubygems'
require 'bundler'
Bundler.setup

require 'sinatra/base'
require 'haml'
require 'sass'
require 'yajl'

require 'mongo'
DB = Mongo::Connection.new.db('memprof_site')

require 'memprof.com'
# $dump = Memprof::Dump.new(:bundler3)
# $dump = Memprof::Dump.new(:supr)
$dump = Memprof::Dump.new(:stdlib)

class MemprofApp < Sinatra::Base
  get '/' do
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

  get '/test' do
    partial :_testview, :layout => (request.xhr? ? false : :ui)
  end

  get '/classview' do
    if of = params[:of] and !of.empty?
      klass = $dump.db.find_one(Yajl.load of)
      subclasses = $dump.subclasses_of(klass).sort_by{ |o| o['name'] || '' }
    elsif where = params[:where] and !where.empty?
      subclasses = [$dump.db.find_one(Yajl.load where)]
    else
      subclasses = [$dump.root_object]
    end

    subclasses.compact!
    subclasses.each do |o|
      o['hasSubclasses'] = $dump.subclasses_of?(o)
    end

    partial :_classview, :layout => (request.xhr? ? false : :ui), :list => subclasses
  end

  get '/namespace' do
    if where = params[:where] and !where.empty?
      obj = $dump.db.find_one(Yajl.load where)
    else
      obj = $dump.root_object
    end

    constants = obj['ivars'].reject{ |k,v| k !~ /^[A-Z]/ }
    names = constants.invert
    classes = $dump.db.find(:type => {:$in => %w[iclass class module]}, :_id => {:$in => constants.values}).to_a.sort_by{ |o| names[o['_id']] || o['name'] }

    classes.each do |o|
      unless o['name'] == 'Object'
        vars = o['ivars'].reject{ |k,v| k !~ /^[A-Z]/ }
        o['hasChildren'] = !!$dump.db.find_one(:type => {:$in => %w[iclass class module]}, :_id => {:$in => vars.values})
      end
    end

    partial :_namespace, :layout => (request.xhr? ? false : :ui), :list => classes, :names => names
  end

  get '/inbound_refs' do
    if root = params[:root]
      list = [$dump.db.find_one(Yajl.load root)]
    elsif where = params[:where]
      list = $dump.refs.find(Yajl.load where)
    else
      list = []
    end

    if list.count == 0
      return '<center>no references found</center>'
    else
      partial :_inbound_refs, :layout => (request.xhr? ? false : :ui), :list => list
    end
  end

  get '/groupview' do
    params[:key] = nil if params[:key] and params[:key].empty?

    if where = params[:where] and !where.empty?
       where = Yajl.load(where)
       key = params[:key] || possible_groupings_for(where).first
    else
      key = (params[:key] ||= 'file')
      where = nil
    end

    if key.nil?
      return '<center>no possible groupings</center>'
    end

    list = $dump.db.group([key], where, {:count=>0}, 'function(d,o){ o.count++ }').sort_by{ |o| -o['count'] }
    partial :_groupview, :layout => (request.xhr? ? false : :ui), :list => list, :key => key, :where => where
  end

  get '/detailview' do
    if where = params[:where]
      list = $dump.db.find(Yajl.load where).limit(200)
    else
      list = [$dump.root_object]
    end

    if list.count == 0
      return '<center>no matching objects</center>'
    elsif list.count == 1
      partial :_detailview, :layout => (request.xhr? ? false : :ui), :obj => list.first
    else
      partial :_listview, :layout => (request.xhr? ? false : :ui), :list => list
    end
  end

  get '/subnav' do
    json :count => $dump.db.find(Yajl.load params[:where]).count
  end

  get %r'/(demo|panel)' do
    subview = params[:subview]

    action = case subview
    when 'subclasses'
      'classview'
    when 'group'
      'groupview'
    when 'detail'
      'detailview'
    when 'references'
      'inbound_refs'
    else
      subview = 'namespace'
      'namespace'
    end

    # TODO: zomg php haxx
    xhr = request.xhr?
    def request.xhr?() true end
    content = send("GET /#{action}")

    partial :_panel, :layout => xhr ? false : :newui, :content => content, :subview => subview
  end

  get '/app.css' do
    content_type('text/css')
    sass :app
  end

  helpers do
    def possible_groupings_for(w)
      possible = %w[ type file ]

      case w['type']
      when 'string', 'hash', 'array'
        possible << 'line' if w.has_key?('file')
        possible << 'length'
        possible << 'data' if w['type'] == 'string'
      when 'module', 'class'
        possible << 'name'
      when 'data', 'object'
        possible << 'class_name'
      when 'node'
        possible << 'node_type'
      end

      possible << 'line' if w.has_key?('file')

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
        "<a href='/panel?subview=detail&where=#{Yajl.dump :_id => val}'>#{val}</a>"
      else
        '&nbsp;'
      end
    end
    def show_val val, as_link = true
      case val
      when nil
        'nil'
      when OrderedHash, /^0x/
        if val.is_a?(OrderedHash)
          obj = val
        else
          obj = $dump.db.find_one(:_id => val)
        end

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
            o = $dump.db.find_one(:_id => parent)
            o['data'].dump
          end
        when 'float'
          num = obj['data']
          "#<Float value=#{num}>"
        when 'hash', 'array'
          "#<#{obj['type'] == 'hash' ? 'Hash' : 'Array'}:#{obj['_id']} length=#{obj['length']}>"
        when 'data', 'object'
          "#<#{obj['class_name'] || 'Object'}:#{obj['_id']}>"
        when 'node'
          "node:#{obj['node_type']}"
        when 'scope'
          vars = obj['variables']
          vars = obj['variables'].keys - ['_','~'] if vars
          "#<Scope:#{obj['_id']}#{vars ? " variables=#{vars.join(', ')}" : nil}>"
        when 'file'
          "#<File:#{obj['_id']}>"
        when 'struct'
          "#<#{obj['class_name'] || 'Struct'}:#{obj['_id']}>"
        else
          obj['_id']
        end

        if as_link
          "<a href='/panel?subview=detail&where=#{Yajl.dump :_id => obj['_id']}'>#{h show}</a>"
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
  enable :static
end

if __FILE__ == $0
  MemprofApp.run!
end
