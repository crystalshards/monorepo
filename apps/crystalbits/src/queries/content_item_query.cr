class ContentItemQuery < ContentItem::BaseQuery
  # The only query a public page is allowed to build from. Every public
  # listing and every public show action starts here, so "approved or nothing"
  # is enforced in one place rather than remembered at each call site.
  def publicly_visible
    state(ContentItem::State::APPROVED)
  end

  def pending_review
    state.in(ContentItem::State::PENDING)
  end

  def by_source_url(url : String)
    source_url(url)
  end

  def machine_drafted_only
    machine_drafted(true)
  end

  # Ordered by when the source published, not when we ingested, so backfilling
  # older feed entries does not reshuffle the top of the index. Every operation
  # sets original_published_at, so the created_at tiebreak only matters for
  # items published on the same date.
  def newest_first
    order_by(:original_published_at, :desc).order_by(:created_at, :desc)
  end

  def oldest_first
    order_by(:created_at, :asc)
  end
end
