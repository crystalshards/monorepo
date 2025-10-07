class Api::Jobs::Show < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/jobs/:id" do
    job = JobQuery.new.find(id)

    json({
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
      active:          job.active,
      created_at:      job.created_at,
      updated_at:      job.updated_at,
    })
  rescue Avram::RecordNotFoundError
    json({error: "Job not found"}, status: 404)
  end
end
