class Jobs::Create < BrowserAction
  post "/jobs" do
    SaveJob.create(params) do |operation, job|
      if job
        flash.success = "Job preview ready! Complete payment to publish."
        redirect to: Jobs::Payment.with(job.id)
      else
        flash.failure = "There was a problem with your job posting"
        html Jobs::NewPage, operation: operation
      end
    end
  end
end
