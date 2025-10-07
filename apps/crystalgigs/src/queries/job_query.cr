class JobQuery < Job::BaseQuery
  def active_only
    active(true)
  end

  def published_only
    published_at.is_not_nil
  end

  def not_expired
    expires_at.is_nil.or { expires_at.gt(Time.utc) }
  end

  def featured_only
    featured(true)
  end

  def remote_only
    remote(true)
  end

  def by_job_type(type : String)
    job_type(type)
  end

  def by_location(location : String)
    self.location.ilike("%#{location}%")
  end

  def search(query : String)
    search_term = "%#{query}%"
    where("title ILIKE ? OR description ILIKE ? OR company_name ILIKE ?",
      search_term, search_term, search_term)
  end

  def recent
    order_by(:published_at, :desc)
  end
end
