class PostQuery < Post::BaseQuery
  def published
    published_at.is_not_nil.published_at.lte(Time.utc)
  end

  def featured_only
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
