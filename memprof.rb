require 'rubygems'

require 'sinatra/base'
require 'haml'
require 'db'

class Memprof < Sinatra::Default

  get '/' do
	haml :main
  end
  
 post '/email' do
	Email.create(:email => params[:email_addr]) if params[:email_addr]
	haml :thanks
  end


  helpers do
    def partial name, locals = {}
      haml name, :layout => false, :locals => locals
    end
  end

  set :server, 'thin'
  set :port, 7006
end

Memprof.run!
