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
    partial :_groupview, :layout => (request.xhr? ? false : :ui)
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
