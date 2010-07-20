class SessionsController < ApplicationController

  def new
    render :partial => 'new'
  end

  def create
    login, password = params[:login].values_at(:login, :password)
    user = User.authenticate(login, password)

    if user
      flash[:notice] = "You have logged in successfully."
      session[:user_id] = user.id
      redirect_to_target_or_default('/')
    else
      if request.xhr?
        render :text => "Login incorrect.", :status => 403
      else
        render :partial => 'new'
      end
    end
  end

  def destroy
    session.delete(:user_id)
    flash[:notice] = "You have been logged out."
    redirect_to '/'
  end

end