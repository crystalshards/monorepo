class SaveJobApplication < JobApplication::SaveOperation
  # A candidate supplies who they are and how to reach them. Everything about
  # the handoff is written by the handoff service, never by a request, so a
  # candidate can never post themselves a "delivered" status.
  permit_columns :candidate_name, :candidate_email, :candidate_phone,
    :resume_url, :cover_letter

  before_save do
    normalize_email
    validate_required job_id, candidate_name, candidate_email
    validate_email_format
    validate_resume_url
    validate_status
  end

  private def normalize_email
    if value = candidate_email.value
      candidate_email.value = value.strip.downcase
    end
  end

  private def validate_email_format
    value = candidate_email.value
    return if value.nil?

    unless value.matches?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      candidate_email.add_error("must be a valid email address")
    end
  end

  private def validate_resume_url
    value = resume_url.value
    return if value.nil? || value.blank?

    unless value.starts_with?("http://") || value.starts_with?("https://")
      resume_url.add_error("must be an http or https URL")
    end
  end

  private def validate_status
    value = handoff_status.value
    return if value.nil?

    unless JobApplication::STATUSES.includes?(value)
      handoff_status.add_error("must be one of: #{JobApplication::STATUSES.join(", ")}")
    end
  end
end
