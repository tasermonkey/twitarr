require 'bcrypt'

class User
  include Mongoid::Document

  USERNAME_REGEX = /^[\w&-]{3,}$/
  DISPLAY_NAME_REGEX = /^[\w\. &-]{3,40}$/

  field :un, as: :username, type: String
  field :pw, as: :password, type: String
  field :ia, as: :is_admin, type: Boolean
  field :st, as: :status, type: String
  field :em, as: :email, type: String
  field :dn, as: :display_name, type: String
  field :ll, as: :last_login, type: DateTime
  field :sq, as: :security_question, type: String
  field :sa, as: :security_answer, type: String

  # noinspection RubyResolve
  before_create :set_profile_image_as_identicon

  validate :valid_username?
  validate :valid_display_name?
  validates :email, format: { with: /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}\b/i, message: 'address is not valid.'}
  validates :security_question, :security_answer, presence: true

  def self.valid_username?(username)
    return false unless username
    !username.match(USERNAME_REGEX).nil?
  end

  def valid_username?
    unless User.valid_username? (username)
      errors.add(:username, 'must be three or more characters and only include letters, numbers, underscore, dash, and ampersand')
    end
  end

  def self.valid_display_name?(name)
    return true unless name
    !name.match(DISPLAY_NAME_REGEX).nil?
  end

  def valid_display_name?
    unless User.valid_display_name? (display_name)
      errors.add(:display_name, 'must be three or more characters and cannot include any of ~!@#$%^*()+=<>{}[]\\|;:/?')
    end
  end

  def empty_password?
    password.nil? || password.empty?
  end

  def set_password(pass)
    self.password = BCrypt::Password.create pass
  end

  def correct_password(pass)
    BCrypt::Password.new(password) == pass
  end

  def update_last_login
    self.last_login = Time.now.to_f
    self
  end

  def username=(val)
    super User.format_username val
  end

  def security_answer=(val)
    super val.andand.downcase.andand.strip
  end

  def security_question=(val)
    super val.andand.strip
  end

  def display_name=(val)
    super val.andand.strip
  end

  def seamails
    Seamail.where(usernames: username).sort_by { |x| x.last_message }.reverse
  end

  def seamail_unread_count
    Seamail.where(usernames: username, unread_users: username).length
  end


  def seamail_count
    Seamail.where(usernames: username).length
  end

  def liked_posts
    ForumPost.where(:likes.in => [self.username]).union(StreamPost.where(:likes.in => [self.username])).order_by(timestamp: :desc)
  end

  def self.format_username(username)
    username.andand.downcase.andand.strip
  end

  def set_profile_image_as_identicon
    identicon = Identicon.create(username)
    save_profile_picture(identicon)
  end

  def self.exist?(username)
    where(username: format_username(username)).exists?
  end

  def self.get(username)
    where(username: format_username(username)).first
  end

  def profile_picture_from_file(temp_file, options = {})
    img = PhotoStore.instance.read_image(temp_file).first
    return img if img.is_a? Hash
    save_profile_picture(img, options)
  end

  # @param [Magick::Image] img
  # @param [hash] options
  def save_profile_picture(img, options = {})
    store_filename = "#{username}.png"
    tmp_store_path = "tmp/#{store_filename}"
    small_thumbnail_width = options[:small_thumbnail_width] || 73
    img.resize_to_fit(small_thumbnail_width, small_thumbnail_width).write tmp_store_path
    small_profile_path = PhotoStore.instance.small_profile_path(store_filename)
    puts "Saving profile image (#{tmp_store_path}) => #{small_profile_path}"
    FileUtils.move tmp_store_path, small_profile_path
    self
  end


  def profile_picture_path
    PhotoStore.instance.small_profile_path("#{username}.png")
  end

  def profile_picture
    PhotoStore.instance.small_profile_img("#{username}.png")
  end
end