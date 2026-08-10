require "../../spec_helper"

describe Newsletter::Subscribe do
  it "creates subscriber with valid email" do
    response = BrowserClient.exec(Newsletter::Subscribe, subscriber: {email: "test@example.com"})

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

  it "accepts the field name the rendered signup form posts" do
    # SaveSubscriber reads params through the raising Avram::Params#nested, so a
    # form field the operation's param_key does not cover raises instead of
    # subscribing. Drive the exact name the page renders through a raw
    # form-encoded body, the way a browser submits it.
    page = BrowserClient.exec(Home::Index).body
    field_name = page.match!(/<input[^>]+type="email"[^>]+name="([^"]+)"/)[1]

    response = BrowserClient.new.exec_raw(
      Newsletter::Subscribe,
      URI::Params.encode({field_name => "wired@example.com"})
    )

    response.status.should eq(HTTP::Status.new(302))
    response.headers["Location"].should contain("/newsletter/confirmation_sent")
    SubscriberQuery.new.by_email("wired@example.com").first?.should_not be_nil
  end
end
