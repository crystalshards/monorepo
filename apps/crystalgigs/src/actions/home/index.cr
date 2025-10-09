class Home::Index < BrowserAction
  get "/" do
    featured_jobs = JobQuery.new
      .active_only
      .published_only
      .not_expired
      .featured_only
      .recent
      .limit(6)

    recent_jobs = JobQuery.new
      .active_only
      .published_only
      .not_expired
      .recent
      .limit(10)

    total_jobs = JobQuery.new
      .active_only
      .published_only
      .not_expired
      .select_count

    total_companies = JobQuery.new
      .active_only
      .published_only
      .not_expired
      .select_count

    html Home::IndexPage,
      featured_jobs: featured_jobs.results,
      recent_jobs: recent_jobs.results,
      total_jobs: total_jobs,
      total_companies: total_companies
  end
end
