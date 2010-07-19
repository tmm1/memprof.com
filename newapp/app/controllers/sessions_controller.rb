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
      render :partial => 'new'
    end
  end

  def destroy
    session.delete(:user_id)
    flash[:notice] = "You have been logged out."
    redirect_to '/'
  end

end