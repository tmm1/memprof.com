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
    partial :_groupview, :layout => (request.xhr? ? false : :ui)
  end

  get '/classview' do
    if params[:where]
      klass = $dump.db.find_one(Yajl.load params[:where])
      subclasses = $dump.subclasses_of(klass).sort_by{ |o| o['name'] || '' }
    else
      subclasses = [$dump.root_object]
    end

    subclasses.each do |o|
      o['hasChildren'] = $dump.subclasses_of?(o)
    end

    partial :_classview, :layout => (request.xhr? ? false : :ui), :list => subclasses
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
