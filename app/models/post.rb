class Post < Message

  TAG_PREFIX = 'tag:%s'
  POST_PREFIX = 'post:%s'
  FAVORITES_PREFIX = 'post-favorites:%s'
  POPULAR_KEY = 'system:popular'

  def tags
    (%W(@#{username}) + message.scan(/[@#]\w+/)).map { |x| x.downcase }.uniq.select { |x| x.length > 2 }
  end

  def score(like_count)
    post_time.to_i / 3600 + like_count
  end

  def json_hash(user_liked, friends_like, other_like)
    { message: message, username: username, post_time: post_time.to_i, post_id: post_id, liked: user_liked, liked_sentence: liked_sentence(user_liked, friends_like, other_like) }
  end

  def liked_sentence(user_liked, friends_like, other_likes)
    likes = []
    likes << 'You' if user_liked
    likes += friends_like
    other_likes = other_likes - likes.count
    likes << "#{other_likes} people" if other_likes > 1
    likes << '1 other person' if other_likes == 1
    return case
             when likes.count > 1
               "#{likes[0..-2].join ', '} and #{likes.last} like this."
             when likes.count > 0
               if likes.first == 'You'
                 'You like this.'
               elsif other_likes > 1
                 "#{likes.first} like this."
               else
                 "#{likes.first} likes this."
               end
           end
  end

  def db_pipeline(db = nil, &block)
    self.class.db_pipeline(db, &block)
  end

  def db_score(db = nil)
    puts db.object_id
    db_pipeline(db) do |db|
      puts db.object_id
      likes = db_likes(db)
      -> { score(likes.call) }
    end
  end

  def db_save
    score = db_score.call
    db_pipeline do |db|
      puts db.object_id
      db.set POST_PREFIX % post_id, to_json
      db.zadd POPULAR_KEY, score, post_id
      tags.each do |tag|
        db.zadd TAG_PREFIX % tag, Time.now.to_i, post_id
      end
    end
  end

  def db_likes(db = nil)
    db_pipeline(db) do |db|
      puts db.object_id
      ret = db.scard(FAVORITES_PREFIX % post_id)
      -> { ret.value }
    end
  end

  def db_json_hash(user, db)
    db_pipeline(db) do |db|
      user_like = db.sismember FAVORITES_PREFIX % post_id, user
      friends_like = db.sinter(FAVORITES_PREFIX % post_id, User::USER_FRIENDS_PREFIX % user)
      other_likes = db_likes(db)
      -> { json_hash(user_like.value, friends_like.value, other_likes.call) }
    end
  end

  def self.db_pipeline(db = nil)
    ret = nil
    if db.nil?
      DbConnectionPool.instance.connection do |db|
        db.pipelined { ret = yield db }
      end
    elsif db.client.is_a? Redis::Pipeline
      ret = yield db
    else
      db.pipelined { ret = yield db }
    end
    ret
  end

  def self.db_call
    DbConnectionPool.instance.connection do |db|
      yield db
    end
  end

  def self.posts_hash(posts, user)
    db_pipeline do |db|
      posts = posts.map { |x| x.db_json_hash user, db }
    end
    posts.map { |x| x.call }
  end

  def self.add_favorite(id, username)
    post = find(id)
    score = post.db_score.call
    db_pipeline do |db|
      db.sadd FAVORITES_PREFIX % id, username
      db.zadd POPULAR_KEY, score, id
    end
  end

  def self.find(post_ids)
    return if post_ids.nil?
    return [] if post_ids.empty?
    db_call do |db|
      if post_ids.respond_to? :map
        post_ids.map do |id|
          Post.new JSON.parse(db.get(POST_PREFIX % id))
        end
      else
        Post.new JSON.parse(db.get(POST_PREFIX % post_ids))
      end
    end
  end

  def self.tagged(tag, start = 0, count = 20)
    db_call do |db|
      find db.zrevrange(TAG_PREFIX % tag.downcase, start, start + count)
    end
  end

  def self.delete(id)
    post = find(id)
    db_pipeline do |db|
      post.tags.each do |tag|
        db.zrem TAG_PREFIX % tag, id
      end
      db.zrem POPULAR_KEY, id
      db.del POST_PREFIX % id
    end
  end

  def self.popular(start = 0, count = 20)
    db_call do |db|
      find db.zrevrange(POPULAR_KEY, start, start + count)
    end
  end

end