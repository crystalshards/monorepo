class SubscriberQuery < Subscriber::BaseQuery
  def active
    confirmed(true).unsubscribed_at.is_nil
  end

  def pending_confirmation
    confirmed(false).unsubscribed_at.is_nil
  end

  def by_email(email_address : String)
    email(email_address)
  end

  def by_confirmation_token(token : String)
    confirmation_token(token)
  end
end
