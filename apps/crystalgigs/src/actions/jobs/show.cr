class Jobs::Show < BrowserAction
  get "/jobs/:job_id" do
    job = JobQuery.new.find(job_id)

    html Jobs::ShowPage, job: job
  end
end
