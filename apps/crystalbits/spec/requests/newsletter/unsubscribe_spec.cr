require "../../spec_helper"

describe Newsletter::Unsubscribe do
  pending "unsubscribes with valid token" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    subscriber = SubscriberFactory.create do |s|
      s.email("test@example.com")
      s.confirmed(true)
      s.confirmation_token("valid-token")
      s.unsubscribed_at(nil)
    end

    response = BrowserClient.exec(Newsletter::Unsubscribe.with("valid-token"))

    response.status.should eq(HTTP::Status.new(200))
    subscriber.reload
    subscriber.unsubscribed_at.should_not be_nil
  end

  pending "shows unsubscribe confirmation message" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    subscriber = SubscriberFactory.create do |s|
      s.confirmed(true)
      s.confirmation_token("valid-token")
      s.unsubscribed_at(nil)
    end

    response = BrowserClient.exec(Newsletter::Unsubscribe.with("valid-token"))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("You've Been Unsubscribed")
  end

  it "redirects for invalid token" do
    response = ApiClient.exec(Newsletter::Unsubscribe.with("invalid-token"))

    response.status.should eq(HTTP::Status.new(302))
  end

  pending "redirects if already unsubscribed" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    subscriber = SubscriberFactory.create do |s|
      s.confirmed(true)
      s.confirmation_token("valid-token")
      s.unsubscribed_at(Time.utc - 1.day)
    end

    response = BrowserClient.exec(Newsletter::Unsubscribe.with("valid-token"))

    response.status.should eq(HTTP::Status.new(302))
  end

  pending "sets unsubscribed_at timestamp" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    subscriber = SubscriberFactory.create do |s|
      s.confirmed(true)
      s.confirmation_token("valid-token")
      s.unsubscribed_at(nil)
    end

    before = Time.utc
    BrowserClient.exec(Newsletter::Unsubscribe.with("valid-token"))
    after = Time.utc

    subscriber.reload
    unsubscribed_at = subscriber.unsubscribed_at.not_nil!
    unsubscribed_at.should be >= before
    unsubscribed_at.should be <= after
  end

  pending "keeps subscriber record but marks as unsubscribed" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    subscriber = SubscriberFactory.create do |s|
      s.email("test@example.com")
      s.confirmed(true)
      s.confirmation_token("valid-token")
      s.unsubscribed_at(nil)
    end

    BrowserClient.exec(Newsletter::Unsubscribe.with("valid-token"))

    # Subscriber still exists
    found = SubscriberQuery.new.by_email("test@example.com").first
    found.id.should eq(subscriber.id)
    found.unsubscribed_at.should_not be_nil
  end
end
