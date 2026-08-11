class SaveAtsConnection < AtsConnection::SaveOperation
  # `provider`, `board_token` and the employer-facing fields are the only
  # things an employer supplies. Sync bookkeeping is written by the importer,
  # never by a request.
  permit_columns :provider, :board_token, :company_name, :company_url,
    :application_email, :active

  before_save do
    normalize_provider
    normalize_board_token
    validate_required user_id, provider, board_token, company_name
    validate_provider_registered
    validate_application_email
  end

  private def normalize_provider
    if value = provider.value
      provider.value = value.strip.downcase
    end
  end

  private def normalize_board_token
    if value = board_token.value
      board_token.value = value.strip
    end
  end

  private def validate_provider_registered
    value = provider.value
    return if value.nil?

    unless CrystalGigs::Ats::Registry.registered?(value)
      provider.add_error(
        "must be one of: #{CrystalGigs::Ats::Registry.keys.join(", ")}"
      )
    end
  end

  private def validate_application_email
    value = application_email.value
    return if value.nil? || value.blank?

    unless value.matches?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      application_email.add_error("must be a valid email address")
    end
  end
end
