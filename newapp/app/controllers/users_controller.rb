class UsersController < ApplicationController

  def new
    @user = User.new
    render :partial => 'new', :locals => {:user => @user}
  end

  def create
    @user = User.new(params[:user])
    if @user.save
      flash[:notice] = "Registration successful!"
      session[:user_id] = @user.id
      redirect_to_target_or_default('/')
    else
      if request.xhr?
        render :text => @user.errors.collect{|p| p.join(" ")}.join("\n"), :status => 500
      else
        render :partial => 'new', :locals => {:user => @user}
      end
    end
  end

end
