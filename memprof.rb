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
      # o['numInstances'] = $dump.db.find(:type => 'object', :class => o['_id']).count
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

  helpers do
    def partial name, locals = {}
      haml name, :layout => locals.delete(:layout) || false, :locals => locals
    end
  end

  set :server, 'thin'
  set :port, 7006
  set :public, File.expand_path('../public', __FILE__)
  enable :static
end

MemprofApp.run!
