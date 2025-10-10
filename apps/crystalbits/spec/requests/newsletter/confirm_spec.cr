require "../../spec_helper"

describe Newsletter::Confirm do
  pending "confirms subscription with valid token" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    subscriber = SubscriberFactory.create do |s|
      s.email("test@example.com")
      s.confirmed(false)
      s.confirmation_token("valid-token")
    end

    response = BrowserClient.exec(Newsletter::Confirm.with("valid-token"))

    response.status.should eq(HTTP::Status.new(200))
    subscriber.reload
    subscriber.confirmed.should be_true
    subscriber.confirmed_at.should_not be_nil
    subscriber.confirmation_token.should be_nil
  end

  pending "shows success message" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    subscriber = SubscriberFactory.create do |s|
      s.confirmed(false)
      s.confirmation_token("valid-token")
    end

    response = BrowserClient.exec(Newsletter::Confirm.with("valid-token"))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("You're Subscribed!")
    response.body.should contain(subscriber.email)
  end

  it "redirects for invalid token" do
    response = ApiClient.exec(Newsletter::Confirm.with("invalid-token"))

    response.status.should eq(HTTP::Status.new(302))
  end

  it "redirects if already confirmed" do
    subscriber = SubscriberFactory.create do |s|
      s.confirmed(true)
      s.confirmation_token("token")
      s.confirmed_at(Time.utc)
    end

    response = ApiClient.exec(Newsletter::Confirm.with("token"))

    response.status.should eq(HTTP::Status.new(302))
  end

  pending "sets confirmed_at timestamp" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    subscriber = SubscriberFactory.create do |s|
      s.confirmed(false)
      s.confirmation_token("valid-token")
    end

    before = Time.utc
    BrowserClient.exec(Newsletter::Confirm.with("valid-token"))
    after = Time.utc

    subscriber.reload
    confirmed_at = subscriber.confirmed_at.not_nil!
    confirmed_at.should be >= before
    confirmed_at.should be <= after
  end

  pending "clears confirmation token after confirming" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    subscriber = SubscriberFactory.create do |s|
      s.confirmed(false)
      s.confirmation_token("valid-token")
    end

    BrowserClient.exec(Newsletter::Confirm.with("valid-token"))

    subscriber.reload
    subscriber.confirmation_token.should be_nil
  end
end
