require 'rubygems'

require 'sinatra/base'
require 'haml'
require 'db'

class MemprofApp < Sinatra::Default
  get '/' do
    haml :main
  end

  post '/email' do
    Email.create(:email => params[:email_addr]) if params[:email_addr]
    haml :thanks
  end

  get '/test' do
    if request.xhr?
      partial :_groupview
    else
      haml :_groupview, :layout => :ui
    end
  end

  helpers do
    def partial name, locals = {}
      haml name, :layout => false, :locals => locals
    end
  end

  set :server, 'thin'
  set :port, 7006
  set :public, File.expand_path('../public', __FILE__)
  enable :static
end

MemprofApp.run!
