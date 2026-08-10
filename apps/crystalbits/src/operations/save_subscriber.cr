class SaveSubscriber < Subscriber::SaveOperation
  permit_columns email, confirmed, confirmed_at, confirmation_token, unsubscribed_at

  before_save do
    # Normalization has to run first so format and uniqueness are checked
    # against the value that actually gets persisted.
    normalize_email
    validate_required email
    validate_email_format
    validate_email_uniqueness
    set_confirmation_token
  end

  private def normalize_email
    email.value = email.value.try(&.strip.downcase)
  end

  private def validate_email_format
    email_value = email.value
    return unless email_value

    unless email_value.matches?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      email.add_error("must be a valid email address")
    end
  end

  private def validate_email_uniqueness
    email_value = email.value
    return unless email_value

    query = SubscriberQuery.new.by_email(email_value)
    if id = record_id
      query = query.id.not.eq(id)
    end

    if query.any?
      email.add_error("is already subscribed")
    end
  end

  private def set_confirmation_token
    # Only issue a token when the subscriber is first created. Regenerating it
    # on every save would undo the confirmation it exists to grant.
    return unless new_record?

    confirmation_token.value = Random::Secure.hex(32)
    confirmed.value = false
  end
end
