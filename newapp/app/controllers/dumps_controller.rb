class DumpsController < ApplicationController
  before_filter :admin_required, :only => [:destroy]
  protect_from_forgery :except => :create

  def create
    tempfile = params[:upload]
    name     = params[:name]
    key      = params[:key]

    user = User.find(:first, :conditions => { :api_key => params[:key] })

    unless user
      render :text => "Bad API key."
      return
    end

    unless tempfile
      render :text => "Failed - no file."
      return
    end

    unless name && !name.empty?
      render :text => "Failed - no dump name."
      return
    end

    dump = Dump.new(:name => name)
    user.dumps << dump
    user.save!

    new_name = File.join(Rails.root, "dumps/#{dump.id}.json.gz")
    tempfile.close
    File.rename(tempfile.path, new_name)

    render :text => "Success! Visit http://www.memprof.com/dump/#{dump.id} to view."
  end

  def destroy
    dump = current_user.dumps.find(params[:id])
    dump.destroy

    datasets = Mongoid.master.connection.db("memprof_datasets")
    datasets.collection(dump.id).drop
    datasets.collection(dump.id + '_refs').drop

    flash[:notice] = "Dump deleted."
    redirect '/'
  end

end
