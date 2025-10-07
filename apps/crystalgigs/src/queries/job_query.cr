class JobQuery < Job::BaseQuery
  def active
    where("active = ?", true)
  end

  def published
    where("published_at IS NOT NULL")
  end

  def not_expired
    where("expires_at IS NULL OR expires_at > ?", Time.utc)
  end

  def featured
    where("featured = ?", true)
  end

  def remote
    where("remote = ?", true)
  end

  def by_job_type(type : String)
    job_type(type)
  end

  def by_location(location : String)
    where("location ILIKE ?", "%#{location}%")
  end

  def search(query : String)
    where("title ILIKE ? OR description ILIKE ? OR company_name ILIKE ?",
      "%#{query}%", "%#{query}%", "%#{query}%")
  end

  def recent
    order_by(:published_at, :desc)
  end
end
