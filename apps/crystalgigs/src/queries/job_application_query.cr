class JobApplicationQuery < JobApplication::BaseQuery
  def for_job(job : Job)
    job_id(job.id)
  end

  # Handoffs an operator needs to look at: the employer never got these.
  def needs_attention
    handoff_status(JobApplication::STATUS_FAILED)
  end

  def delivered_only
    handoff_status(JobApplication::STATUS_DELIVERED)
  end

  def recent
    order_by(:created_at, :desc)
  end
end
