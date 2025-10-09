class SaveSubscriber < Subscriber::SaveOperation
  permit_columns email, confirmed, confirmed_at, confirmation_token, unsubscribed_at

  before_save do
    validate_required email
    validate_email_format
    validate_email_uniqueness
    normalize_email
    set_confirmation_token
  end

  private def validate_email_format
    return unless email.value

    email_value = email.value.to_s
    unless email_value.matches?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      email.add_error("must be a valid email address")
    end
  end

  private def validate_email_uniqueness
    return unless email.value

    existing = SubscriberQuery.new.by_email(email.value.to_s).first?
    if existing
      email.add_error("is already subscribed")
    end
  end

  private def normalize_email
    email.value = email.value.try(&.downcase.strip)
  end

  private def set_confirmation_token
    confirmation_token.value = Random::Secure.hex(32)
    confirmed.value = false
  end
end
