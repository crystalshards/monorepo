# A candidate applies to a posting.
#
# The response is derived from the stored handoff status, never from the fact
# that a row was written. If the employer's system did not take the
# application, the candidate is told exactly that and given the next step.
class Api::Jobs::Applications::Create < ApiAction
  include Api::Auth::SkipRequireAuthToken

  # HTTP status per handoff outcome. A failed handoff is a 502: the request
  # was fine, the downstream system was not.
  STATUS_CODES = {
    JobApplication::STATUS_DELIVERED => 201,
    JobApplication::STATUS_REFERRED  => 202,
    JobApplication::STATUS_FAILED    => 502,
    JobApplication::STATUS_PENDING   => 202,
  }

  post "/api/jobs/:job_id/applications" do
    job = JobQuery.new.id(job_id.to_i64).first?

    if job.nil?
      json(
        ErrorSerializer.new(message: "Job not found.", details: "No job with that id."),
        status: 404
      )
    elsif !job.active || job.delisted?
      json(
        ErrorSerializer.new(
          message: "This posting is no longer accepting applications.",
          details: job.delisted? ? "The employer removed it from their job board." : "The posting is closed."
        ),
        status: 410
      )
    else
      SaveJobApplication.create(params, job_id: job.id) do |operation, application|
        if application
          handed_off = CrystalGigs::Ats::ApplicationHandoff.new.deliver(application, job)
          json(serialize(handed_off, job), status: STATUS_CODES[handed_off.handoff_status]? || 202)
        else
          json({errors: operation.errors.map { |attr, msgs| {attr.to_s => msgs} }}, status: 422)
        end
      end
    end
  end

  private def serialize(application : JobApplication, job : Job)
    {
      id:     application.id,
      job_id: job.id,
      # The honest answer, straight off the stored record.
      submitted: application.delivered?,
      status:    application.handoff_status,
      method:    application.handoff_method,
      message:   application.candidate_message,
      # Where to finish, when we could not finish it for them.
      next_step:  application.delivered? ? nil : job.apply_url,
      applied_at: application.handed_off_at,
    }
  end
end
