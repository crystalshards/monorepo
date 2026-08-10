class Jobs::Index < BrowserAction
  param page : Int32 = 1
  param query : String?
  param location : String?
  param job_type : String?
  param remote : Bool?

  get "/jobs" do
    per_page = 20
    search_term = normalized_query

    jobs_query = JobQuery.new
      .active_only
      .published_only
      .not_expired
      .recent

    if q = search_term
      jobs_query = jobs_query.search(q)
    end

    if loc = location
      jobs_query = jobs_query.by_location(loc)
    end

    if jt = job_type
      jobs_query = jobs_query.by_job_type(jt)
    end

    if remote
      jobs_query = jobs_query.remote_only
    end

    total_count = jobs_query.clone.select_count
    total_pages = (total_count / per_page.to_f).ceil.to_i
    current_page = [[page, 1].max, [total_pages, 1].max].min

    jobs = jobs_query
      .limit(per_page)
      .offset((current_page - 1) * per_page)
      .results

    html Jobs::IndexPage,
      jobs: jobs,
      query: search_term,
      location: location,
      job_type: job_type,
      remote: remote,
      current_page: current_page,
      total_pages: total_pages,
      total_count: total_count
  end

  # A blank query param ("" or whitespace) is no query at all: it should
  # neither filter the results nor be named in the results count.
  private def normalized_query : String?
    q = query
    return if q.nil?
    q.strip.empty? ? nil : q
  end
end
