class ApplicationController < ActionController::Base
  include Authentication
  protect_from_forgery
  layout 'application'
end
