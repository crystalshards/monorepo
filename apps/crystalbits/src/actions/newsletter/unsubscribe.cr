class Newsletter::Unsubscribe < BrowserAction
  get "/newsletter/unsubscribe/:token" do
    subscriber = SubscriberQuery.new.by_confirmation_token(token).first?

    if subscriber && subscriber.unsubscribed_at.nil?
      subscriber.unsubscribed_at = Time.utc
      subscriber.save

      flash.success = "You've been unsubscribed from our newsletter."
      html UnsubscribedPage, subscriber: subscriber
    else
      flash.failure = "Invalid unsubscribe link."
      redirect to: Home::Index
    end
  end
end
