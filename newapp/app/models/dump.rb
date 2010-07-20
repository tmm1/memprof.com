class Dump
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name
  field :status, :default => 'pending'
  field :private, :type => Boolean, :default => true
  embedded_in :user, :inverse_of => :dumps

end
