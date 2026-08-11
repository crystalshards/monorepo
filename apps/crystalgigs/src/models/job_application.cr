# A candidate application and the record of what happened when we tried to
# hand it to the employer's system.
#
# `handoff_status` is the honest answer to "did this reach the employer?" and
# is what every candidate-facing response is derived from.
class JobApplication < BaseModel
  # Waiting on a handoff attempt.
  STATUS_PENDING = "pending"
  # The employer's system accepted it: the ATS API returned success, or the
  # application email was sent.
  STATUS_DELIVERED = "delivered"
  # We could not submit on the candidate's behalf and pointed them at the
  # employer's own apply page. Not an application yet.
  STATUS_REFERRED = "referred"
  # A handoff was attempted and did not land anywhere.
  STATUS_FAILED = "failed"

  STATUSES = [STATUS_PENDING, STATUS_DELIVERED, STATUS_REFERRED, STATUS_FAILED]

  METHOD_ATS_API   = "ats_api"
  METHOD_EMAIL     = "email"
  METHOD_APPLY_URL = "apply_url"

  METHODS = [METHOD_ATS_API, METHOD_EMAIL, METHOD_APPLY_URL]

  table do
    belongs_to job : Job

    column candidate_name : String
    column candidate_email : String
    column candidate_phone : String?
    column resume_url : String?
    column cover_letter : String?

    column handoff_method : String?
    column handoff_status : String = STATUS_PENDING
    column handoff_reference : String?
    column handoff_error : String?
    column handed_off_at : Time?
  end

  def pending? : Bool
    handoff_status == STATUS_PENDING
  end

  # True only when the employer's system actually took the application.
  def delivered? : Bool
    handoff_status == STATUS_DELIVERED
  end

  def referred? : Bool
    handoff_status == STATUS_REFERRED
  end

  def failed? : Bool
    handoff_status == STATUS_FAILED
  end

  # The single source of truth for what a candidate is told.
  def candidate_message : String
    case handoff_status
    when STATUS_DELIVERED
      "Your application was sent to the employer."
    when STATUS_REFERRED
      "We could not submit for you. Finish your application on the employer's site."
    when STATUS_FAILED
      "We could not deliver your application to the employer. Nothing was submitted."
    else
      "Your application is waiting to be sent to the employer."
    end
  end
end
