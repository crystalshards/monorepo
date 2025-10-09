class Newsletter::Confirm < BrowserAction
  get "/newsletter/confirm/:token" do
    subscriber = SubscriberQuery.new.by_confirmation_token(token).first?

    if subscriber && !subscriber.confirmed
      SaveSubscriber.update!(subscriber,
        confirmed: true,
        confirmed_at: Time.utc,
        confirmation_token: nil
      )

      flash.success = "Your subscription is confirmed! Thank you for subscribing."
      html ConfirmedPage, subscriber: subscriber
    else
      flash.failure = "Invalid or expired confirmation link."
      redirect to: Home::Index
    end
  end
end
