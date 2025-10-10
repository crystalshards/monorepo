require "../../spec_helper"

describe Newsletter::Subscribe do
  it "creates subscriber with valid email" do
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

  it "redirects to confirmation sent page" do
    response = BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "test@example.com"})

    response.status.should eq(HTTP::Status.new(302))
    response.headers["Location"].should contain("/newsletter/confirmation_sent")
  end

  it "normalizes email to lowercase" do
    BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "Test@EXAMPLE.COM"})

    subscriber = SubscriberQuery.new.by_email("test@example.com").first
    subscriber.email.should eq("test@example.com")
  end

  it "trims whitespace from email" do
    BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "  test@example.com  "})

    subscriber = SubscriberQuery.new.by_email("test@example.com").first
    subscriber.email.should eq("test@example.com")
  end

  it "rejects invalid email format" do
    response = BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "not-an-email"})

    response.status.should eq(HTTP::Status.new(302))
    SubscriberQuery.new.select_count.should eq(0)
  end

  it "rejects duplicate email" do
    SubscriberFactory.create &.email("test@example.com")

    response = BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "test@example.com"})

    response.status.should eq(HTTP::Status.new(302))
    SubscriberQuery.new.select_count.should eq(1)
  end

  it "requires email" do
    response = BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: ""})

    response.status.should eq(HTTP::Status.new(302))
    SubscriberQuery.new.select_count.should eq(0)
  end

  it "generates unique confirmation token" do
    BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "test1@example.com"})
    BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "test2@example.com"})

    subscriber1 = SubscriberQuery.new.by_email("test1@example.com").first
    subscriber2 = SubscriberQuery.new.by_email("test2@example.com").first

    subscriber1.confirmation_token.should_not eq(subscriber2.confirmation_token)
  end
end
