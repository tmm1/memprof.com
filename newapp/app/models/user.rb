class User
  include Mongoid::Document
  include Mongoid::Timestamps

  field :username
  field :name
  field :email
  field :encrypted_password
  field :ip
  field :api_key, :default => SecureRandom.hex(8)
  field :admin, :type => Boolean, :default => false
  embeds_many :dumps

  validates_presence_of :username, :name, :email, :encrypted_password, :api_key

  attr_accessor :password, :password_confirmation
  validates_presence_of :password, :on => :create
  validates_confirmation_of :password
  validates_length_of :password, :minimum => 4, :allow_blank => true

  before_validation :encrypt_password

  def is_admin?
    admin
  end

  def encrypt_password
    if password && !password.blank?
      self.encrypted_password = BCrypt::Password.create(password).to_s
    end
  end

  def self.authenticate(user, pass)
    user = User.find(:first, :conditions => { :email => user }) ||
           User.find(:first, :conditions => { :username => user })

    if user && ::BCrypt::Password.new(user.encrypted_password) == pass
      user
    else
      nil
    end
  end

end
