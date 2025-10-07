class PostQuery < Post::BaseQuery
  def published
    where_not_nil(:published_at).where("published_at <= ?", Time.utc)
  end

  def featured
    featured(true)
  end

  def by_tag(tag : String)
    where("? = ANY(tags)", tag)
  end

  def search(query : String)
    where("title ILIKE ? OR content ILIKE ?", "%#{query}%", "%#{query}%")
  end

  def recent
    order_by(:published_at, :desc)
  end

  def popular
    order_by(:view_count, :desc)
  end
end
