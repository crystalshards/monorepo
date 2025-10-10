class Jobs::Create < BrowserAction
  post "/jobs" do
    SaveJob.create(params) do |operation, job|
      if job
        job.expires_at = Time.utc + 60.days
        job.active = true
        job.save!

        flash.success = "Job posting created! Please complete payment to publish."
        redirect to: Jobs::Payment.with(job.id)
      else
        flash.failure = "Could not create job posting. Please check the errors below."
        html Jobs::NewPage, operation: operation
      end
    end
  end
end
