# noinspection RubyStringKeysInHashInspection
class StreamPost
  include Mongoid::Document
  include Twitter::Extractor

  field :au, as: :author, type: String
  field :tx, as: :text, type: String
  field :ts, as: :timestamp, type: Time
  field :p, as: :photo, type: String
  field :lk, as: :likes, type: Array, default: []
  field :ht, as: :hash_tags, type: Array
  field :mn, as: :mentions, type: Array
  field :et, as: :entities, type: Array

  validates :text, :author, :timestamp, presence: true
  validate :validate_author

  # 1 = ASC, -1 DESC
  index :likes => 1
  index :timestamp => -1
  index :author => 1
  index :mentions => 1
  index :hash_tags => 1

  before_validation :parse_hash_tags

  def validate_author
    return if author.blank?
    unless User.exist? author
      errors[:base] << "#{author} is not a valid username"
    end
  end

  def add_like(username)
    StreamPost.
        where(id: id).
        find_and_modify({ '$addToSet' => { lk: username } }, new: true)
  end

  def remove_like(username)
    StreamPost.
        where(id: id).
        find_and_modify({ '$pull' => { lk: username } }, new: true)
  end

  def self.at_or_before(ms_since_epoch, filter_author = nil)
    query = where(:timestamp.lte => Time.at(ms_since_epoch.to_i / 1000.0))
    query = query.where(:author => filter_author) if filter_author
    query
  end

  def self.at_or_after(ms_since_epoch, filter_author = nil)
    query = where(:timestamp.gte => Time.at(ms_since_epoch.to_i / 1000.0))
    query = query.where(:author => filter_author) if filter_author
    query
  end

  # noinspection RubyResolve
  def parse_hash_tags
    self.entities = extract_entities_with_indices text
    self.hash_tags = []
    self.mentions = []
    entities.each do |entity|
      if entity.has_key? :hashtag
        self.hash_tags << entity[:hashtag]
      elsif entity.has_key? :screen_name
        self.mentions << entity[:screen_name]
      end
    end
  end

  def likes
    self.likes = [] if super.nil?
    super
  end

end