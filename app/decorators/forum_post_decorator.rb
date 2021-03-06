class ForumPostDecorator < Draper::Decorator
  delegate_all


  def to_hash
    {
        id: id.to_s,
        author: author,
        text: text,
        timestamp: timestamp,
        likes: likes,
        likes_counts: likes.length,
        photos: photos || []
    }
  end

end