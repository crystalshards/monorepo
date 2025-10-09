class Newsletter::Confirm < BrowserAction
  get "/newsletter/confirm/:token" do
    subscriber = SubscriberQuery.new.by_confirmation_token(token).first?

    if subscriber && !subscriber.confirmed
      subscriber.confirmed = true
      subscriber.confirmed_at = Time.utc
      subscriber.confirmation_token = nil
      subscriber.save

      flash.success = "Your subscription is confirmed! Thank you for subscribing."
      html ConfirmedPage, subscriber: subscriber
    else
      flash.failure = "Invalid or expired confirmation link."
      redirect to: Home::Index
    end
  end
end
