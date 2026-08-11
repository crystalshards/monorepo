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

  # Ordering for the promotable ad feed. Featured pays for the top slot, and
  # within each tier the newest posting wins, so a stale featured job cannot
  # sit at the top of three other sites forever.
  #
  # Two order_by calls, not one: Avram appends orders in call order, so this
  # is `ORDER BY featured DESC, published_at DESC`.
  def promoted_first
    order_by(:featured, :desc).order_by(:published_at, :desc)
  end

  # Postings still carried by their source. An imported posting that vanished
  # from the employer's board is stamped with `delisted_at` rather than
  # deleted, so existing links and applications still resolve, but it should
  # not be listed or advertised anywhere.
  def not_delisted
    delisted_at.is_nil
  end

  def imported_only
    source.not.eq(Job::SOURCE_DIRECT)
  end

  def from_connection(connection : AtsConnection)
    ats_connection_id(connection.id)
  end

  # The import dedupe key. Scoped to the connection so a provider that
  # numbers postings per board cannot make one employer's sync collide with
  # another's. See the comment on the unique index in migration 5.
  def for_import(connection : AtsConnection, external_id : String)
    ats_connection_id(connection.id).external_id(external_id)
  end
end
