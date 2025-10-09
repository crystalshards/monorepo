class Jobs::Index < BrowserAction
  get "/jobs" do
    query = params.get?(:query)
    location = params.get?(:location)
    remote = params.get?(:remote)
    job_type = params.get?(:job_type)
    page = params.get?(:page).try(&.to_i) || 1

    jobs_query = JobQuery.new
      .active_only
      .published_only
      .not_expired
      .recent

    jobs_query = jobs_query.search(query) if query && !query.empty?
    jobs_query = jobs_query.by_location(location) if location && !location.empty?
    jobs_query = jobs_query.remote_only if remote == "true"
    jobs_query = jobs_query.by_job_type(job_type) if job_type && !job_type.empty?

    paginated_jobs = jobs_query.paginate(page: page, per_page: 20)

    html Jobs::IndexPage,
      jobs: paginated_jobs.results,
      query: query,
      location: location,
      remote: remote,
      job_type: job_type,
      page: page,
      total_pages: paginated_jobs.pages
  end
end
