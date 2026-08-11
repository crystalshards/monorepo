class Api::Ads::Index < ApiAction
  include Api::Auth::SkipRequireAuthToken

  # The promotable feed the sibling sites render as an ad strip. It is
  # deliberately not `/api/jobs` with different params:
  #
  # - `/api/jobs` is the job board's own API. It serves descriptions, salary
  #   bands, contact emails and pagination metadata, and it grows whenever the
  #   board needs a new field. An ad needs six fields and nothing else, so
  #   pinning them here keeps a change to the board's API from silently
  #   widening what three other sites put on every page.
  # - Only this feed is safe to cache publicly. `/api/jobs` answers filtered,
  #   caller-specific queries; this answers one question with one answer.
  #
  # `url` is the CrystalGigs job page, never the employer's apply_url. The ad
  # exists to send readers to the board, and it keeps a third-party URL that
  # an employer typed out of three other sites' markup.
  DEFAULT_LIMIT = 3

  # An ad strip is a handful of rows. The cap is the contract, not a
  # suggestion: a caller asking for 500 gets 10, so a consuming site cannot
  # turn a page render into a large response no matter what it sends.
  MAX_LIMIT = 10

  # Job postings change on the order of hours. Five minutes is short enough
  # that a newly published job appears quickly and long enough that three
  # sites rendering on every request do not each hit the database.
  CACHE_SECONDS = 300

  get "/api/ads" do
    limit = clamped_limit

    # `not_delisted` is not redundant with `active_only`. An imported posting
    # that vanished from the employer's board is deactivated and stamped, but
    # the stamp is the durable fact: anyone flipping `active` back on must not
    # quietly resume advertising a role that no longer exists, on three sites
    # that cannot check.
    jobs = JobQuery.new
      .active_only
      .published_only
      .not_expired
      .not_delisted
      .promoted_first
      .limit(limit)

    # Public because the response is identical for every caller: no auth, no
    # cookies, no per-caller filtering. stale-while-revalidate lets a cache
    # keep serving the last good copy while it refreshes, which is exactly
    # what an ad strip wants: never a gap, occasionally a few minutes old.
    response.headers["Cache-Control"] =
      "public, max-age=#{CACHE_SECONDS}, stale-while-revalidate=#{CACHE_SECONDS * 2}"

    json({jobs: jobs.map { |job| serialize_ad(job) }})
  end

  private def clamped_limit : Int32
    requested = params.get?(:limit).try(&.to_i?) || DEFAULT_LIMIT
    requested.clamp(1, MAX_LIMIT)
  end

  private def serialize_ad(job : Job)
    {
      title:    job.title,
      company:  job.company_name,
      location: job.location,
      remote:   job.remote,
      url:      Jobs::Show.with(job.id).url,
      featured: job.featured,
    }
  end
end
