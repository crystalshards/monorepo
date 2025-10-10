require "../../spec_helper"

describe Newsletter::Subscribe do
  pending "creates subscriber with valid email" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    # BrowserClient currently sends JSON body, but BrowserActions expect form-encoded data
    response = BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "test@example.com"})

    if response.status.to_i != 302
      puts "\n\n=== DEBUG: Response Status: #{response.status} ==="
      puts "=== DEBUG: Full Response Body: ==="
      puts response.body
      puts "=== DEBUG: End Response Body ==="
    end
    response.status.should eq(HTTP::Status.new(302)) # Redirect
    subscriber = SubscriberQuery.new.by_email("test@example.com").first
    subscriber.email.should eq("test@example.com")
    subscriber.confirmed.should be_false
    subscriber.confirmation_token.should_not be_nil
  end

  pending "redirects to confirmation sent page" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    response = BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "test@example.com"})

    response.status.should eq(HTTP::Status.new(302))
    response.headers["Location"].should contain("/newsletter/confirmation_sent")
  end

  pending "normalizes email to lowercase" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "Test@EXAMPLE.COM"})

    subscriber = SubscriberQuery.new.by_email("test@example.com").first
    subscriber.email.should eq("test@example.com")
  end

  pending "trims whitespace from email" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "  test@example.com  "})

    subscriber = SubscriberQuery.new.by_email("test@example.com").first
    subscriber.email.should eq("test@example.com")
  end

  pending "rejects invalid email format" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    response = BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "not-an-email"})

    response.status.should eq(HTTP::Status.new(302))
    SubscriberQuery.new.select_count.should eq(0)
  end

  pending "rejects duplicate email" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    SubscriberFactory.create &.email("test@example.com")

    response = BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "test@example.com"})

    response.status.should eq(HTTP::Status.new(302))
    SubscriberQuery.new.select_count.should eq(1)
  end

  pending "requires email" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    response = BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: ""})

    response.status.should eq(HTTP::Status.new(302))
    SubscriberQuery.new.select_count.should eq(0)
  end

  pending "generates unique confirmation token" do
    # TODO: Fix BrowserClient to send form-encoded data instead of JSON
    # See issue #49 for investigation details
    BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "test1@example.com"})
    BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "test2@example.com"})

    subscriber1 = SubscriberQuery.new.by_email("test1@example.com").first
    subscriber2 = SubscriberQuery.new.by_email("test2@example.com").first

    subscriber1.confirmation_token.should_not eq(subscriber2.confirmation_token)
  end
end
