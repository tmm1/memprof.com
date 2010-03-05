require 'rubygems'

require 'sinatra/base'
require 'haml'
require 'db'
require 'yajl'

require 'memprof.com'
$dump = Memprof::Dump.new(:hr)

class MemprofApp < Sinatra::Default
  get '/' do
    haml :main
  end

  post '/email' do
    Email.create(:email => params[:email_addr]) if params[:email_addr]
    haml :thanks
  end

  get '/test' do
    partial :_testview, :layout => (request.xhr? ? false : :ui)
  end

  get '/classview' do
    if where = params[:where]
      klass = $dump.db.find_one(Yajl.load where)
      subclasses = $dump.subclasses_of(klass).sort_by{ |o| o['name'] || '' }
    elsif root = params[:root]
      subclasses = [$dump.db.find_one(Yajl.load root)]
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
    if where = params[:where]
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

    partial :_inbound_refs, :layout => (request.xhr? ? false : :ui), :list => list
  end

  get '/groupview' do
    if key = params[:key]
      where = params[:where] ? Yajl.load(params[:where]) : nil
    else
      key = 'file'
      where = nil
    end

    list = $dump.db.group([key], where, {:count=>0}, 'function(d,o){ o.count++ }', true).sort_by{ |o| -o['count'] }
    partial :_groupview, :layout => (request.xhr? ? false : :ui), :list => list, :key => key, :where => where
  end

  get '/detailview' do
    if where = params[:where]
      obj = $dump.db.find_one(Yajl.load where)
    else
      obj = $dump.root_object
    end

    partial :_detailview, :layout => (request.xhr? ? false : :ui), :obj => obj
  end

  get '/listview' do
    if where = params[:where]
      list = $dump.db.find(Yajl.load where)
    else
      list = $dump.db.find(:type => 'class')
    end

    # TODO: this needs pagination BIG TIME
    partial :_listview, :layout => (request.xhr? ? false : :ui), :list => list
  end

  helpers do
    def partial name, locals = {}
      haml name, :layout => locals.delete(:layout) || false, :locals => locals
    end
    def show_addr val
      if val =~ /^0x/
        "<a href='/detailview?where=#{Yajl.dump :_id => val}'>#{val}</a>"
      else
        '&nbsp;'
      end
    end
    def show_val val
      case val
      when nil
        'nil'
      when /^0x/
        obj = $dump.db.find_one(:_id => val)
        show = case obj['type']
        when 'class', 'module', 'iclass'
          if name = obj['name']
            "#{name}"
          else
            "#&lt;#{obj['type'] == 'class' ? 'Class' : 'Module'}:#{val}>"
          end
        when 'string'
          if str = obj['data']
            str.dump
          elsif parent = obj['shared']
            o = $dump.db.find_one(:_id => parent)
            o['data'].dump
          end
        when 'float'
          num = obj['data']
          "#&lt;Float value=#{num}>"
        when 'hash', 'array'
          "#&lt;#{obj['type'] == 'hash' ? 'Hash' : 'Array'}:#{obj['_id']} length=#{obj['length']}>"
        when 'data', 'object'
          "#&lt;#{obj['class_name'] || 'Object'}:#{obj['_id']}>"
        when 'node'
          "node:#{obj['node_type']}"
        when 'scope'
          vars = obj['variables']
          vars = obj['variables'].keys - ['_','~'] if vars
          "#&lt;Scope:#{obj['_id']}#{vars ? " variables=#{vars.join(', ')}" : nil}>"
        else
          val
        end

        "<a href='/detailview?where=#{Yajl.dump :_id => val}'>#{show}</a>"
      else
        val
      end
    end
  end

  set :server, 'thin'
  set :port, 7006
  set :public, File.expand_path('../public', __FILE__)
  enable :static
end

MemprofApp.run!
