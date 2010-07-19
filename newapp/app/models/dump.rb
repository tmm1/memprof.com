class Dump
  include Mongoid::Document

  field :name
  field :user_id
  field :status, :default => 'pending'
  field :private, :type => Boolean, :default => true
  field :created_at, :type => Time, :default => Time.now

  validates_presence_of :user_id
end
