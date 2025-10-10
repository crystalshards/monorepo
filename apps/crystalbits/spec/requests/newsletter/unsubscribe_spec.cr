require "../../spec_helper"

describe Newsletter::Unsubscribe do
  it "unsubscribes with valid token" do
    subscriber = SubscriberFactory.create do |s|
      s.email("test@example.com")
      s.confirmed(true)
      s.confirmation_token("valid-token")
      s.unsubscribed_at(nil)
    end

    response = ApiClient.exec(Newsletter::Unsubscribe.with("valid-token"))

    response.should send_http_status(200)
    subscriber.reload
    subscriber.unsubscribed_at.should_not be_nil
  end

  it "shows unsubscribe confirmation message" do
    subscriber = SubscriberFactory.create do |s|
      s.confirmed(true)
      s.confirmation_token("valid-token")
      s.unsubscribed_at(nil)
    end

    response = ApiClient.exec(Newsletter::Unsubscribe.with("valid-token"))

    response.should send_http_status(200)
    response.body.should contain("You've Been Unsubscribed")
  end

  it "redirects for invalid token" do
    response = ApiClient.exec(Newsletter::Unsubscribe.with("invalid-token"))

    response.should send_http_status(302)
  end

  it "redirects if already unsubscribed" do
    subscriber = SubscriberFactory.create do |s|
      s.confirmed(true)
      s.confirmation_token("valid-token")
      s.unsubscribed_at(Time.utc - 1.day)
    end

    response = ApiClient.exec(Newsletter::Unsubscribe.with("valid-token"))

    response.should send_http_status(302)
  end

  it "sets unsubscribed_at timestamp" do
    subscriber = SubscriberFactory.create do |s|
      s.confirmed(true)
      s.confirmation_token("valid-token")
      s.unsubscribed_at(nil)
    end

    before = Time.utc
    ApiClient.exec(Newsletter::Unsubscribe.with("valid-token"))
    after = Time.utc

    subscriber.reload
    unsubscribed_at = subscriber.unsubscribed_at.not_nil!
    unsubscribed_at.should be >= before
    unsubscribed_at.should be <= after
  end

  it "keeps subscriber record but marks as unsubscribed" do
    subscriber = SubscriberFactory.create do |s|
      s.email("test@example.com")
      s.confirmed(true)
      s.confirmation_token("valid-token")
      s.unsubscribed_at(nil)
    end

    ApiClient.exec(Newsletter::Unsubscribe.with("valid-token"))

    # Subscriber still exists
    found = SubscriberQuery.new.by_email("test@example.com").first
    found.id.should eq(subscriber.id)
    found.unsubscribed_at.should_not be_nil
  end
end
