class Jobs::Payment < BrowserAction
  get "/jobs/:job_id/payment" do
    job = JobQuery.new.find(job_id)

    if job.published_at
      flash.info = "This job has already been published"
      redirect to: Jobs::Show.with(job.id)
    else
      html Jobs::PaymentPage, job: job
    end
  end
end
