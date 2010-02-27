require 'rubygems'
require 'sequel'
require 'date'
require 'time'

DB = Sequel.connect(ENV['DATABASE_URL'] || 'mysql://root@localhost/memprof')

unless DB.table_exists? :emails
  DB.create_table :emails do
    primary_key :id
    varchar :email   
    datetime :created_at
  
    index :email
  end
end

class Email < Sequel::Model(:emails)
  before_create { self.created_at = Time.now }  
end
