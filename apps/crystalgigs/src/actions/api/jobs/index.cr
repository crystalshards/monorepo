class Api::Jobs::Index < ApiAction
  get "/api/jobs" do
    page = params.get?(:page).try(&.to_i) || 1
    per_page = params.get?(:per_page).try(&.to_i) || 20
    per_page = [per_page, 100].min

    query = JobQuery.new
      .active
      .published
      .not_expired
      .recent

    if job_type = params.get?(:job_type)
      query = query.by_job_type(job_type)
    end

    if location = params.get?(:location)
      query = query.by_location(location)
    end

    if params.get?(:remote) == "true"
      query = query.remote
    end

    if search_query = params.get?(:q)
      query = query.search(search_query)
    end

    if params.get?(:featured) == "true"
      query = query.featured
    end

    paginated_jobs = query.paginate(page: page, per_page: per_page)
    total_count = query.select_count

    json({
      jobs:     paginated_jobs.map { |job| serialize_job(job) },
      page:     page,
      per_page: per_page,
      total:    total_count,
    })
  end

  private def serialize_job(job : Job)
    {
      id:              job.id,
      title:           job.title,
      description:     job.description,
      company_name:    job.company_name,
      company_url:     job.company_url,
      location:        job.location,
      remote:          job.remote,
      job_type:        job.job_type,
      salary_min:      job.salary_min,
      salary_max:      job.salary_max,
      salary_currency: job.salary_currency,
      apply_url:       job.apply_url,
      apply_email:     job.apply_email,
      tags:            job.tags,
      published_at:    job.published_at,
      expires_at:      job.expires_at,
      featured:        job.featured,
      created_at:      job.created_at,
      updated_at:      job.updated_at,
    }
  end
end
