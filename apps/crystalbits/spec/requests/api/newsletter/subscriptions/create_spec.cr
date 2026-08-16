require "../../../../spec_helper"

describe Api::Newsletter::Subscriptions::Create do
  it "creates an unconfirmed subscriber and sends one confirmation email" do
    response = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "reader@example.com")

    response.status.should eq(HTTP::Status.new(302))
    response.headers["Location"].should contain("/newsletter/confirmation_sent")

    subscriber = SubscriberQuery.new.by_email("reader@example.com").first
    subscriber.confirmed.should be_false
    subscriber.confirmation_token.should_not be_nil

    Carbon::DevAdapter.delivered_emails.size.should eq(1)
    Carbon::DevAdapter.delivered_emails.first.to.should eq([Carbon::Address.new("reader@example.com")])
  end

  it "delivers a confirmation link that confirms the subscriber" do
    BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "reader@example.com")

    subscriber = SubscriberQuery.new.by_email("reader@example.com").first
    response = BrowserClient.exec(Newsletter::Confirm.with(subscriber.confirmation_token.not_nil!))

    response.status.should eq(HTTP::Status.new(200))
    subscriber.reload.confirmed.should be_true
  end

  it "answers an already subscribed address identically to a new one" do
    SubscriberFactory.create &.email("known@example.com")

    known = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "known@example.com")
    fresh = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "fresh@example.com")

    known.status.should eq(fresh.status)
    known.headers["Location"].should eq(fresh.headers["Location"])
    known.body.should eq(fresh.body)
  end

  it "answers an already confirmed address identically to a new one, and sends nothing" do
    SubscriberFactory.create &.email("confirmed@example.com").confirmed(true)

    confirmed = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "confirmed@example.com")
    fresh = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "fresh@example.com")

    confirmed.status.should eq(fresh.status)
    confirmed.headers["Location"].should eq(fresh.headers["Location"])
    confirmed.body.should eq(fresh.body)

    # Only the fresh address got mail. Confirming again would tell the
    # submitter which one was already confirmed.
    delivered_to = Carbon::DevAdapter.delivered_emails.flat_map(&.to)
    delivered_to.should eq([Carbon::Address.new("fresh@example.com")])
  end

  it "does not send a second confirmation to a rapid second request" do
    first = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "reader@example.com")
    second = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "reader@example.com")

    second.status.should eq(first.status)
    second.headers["Location"].should eq(first.headers["Location"])
    Carbon::DevAdapter.delivered_emails.size.should eq(1)
  end

  it "refuses obvious junk without creating or sending anything" do
    response = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "not-an-email")

    response.status.should eq(HTTP::Status.new(302))
    response.headers["Location"].should contain("/newsletter/confirmation_sent")
    SubscriberQuery.new.select_count.should eq(0)
    Carbon::DevAdapter.delivered_emails.should be_empty
  end

  it "treats a missing email field as junk" do
    response = BrowserClient.new.exec_raw(Api::Newsletter::Subscriptions::Create, "")

    response.status.should eq(HTTP::Status.new(302))
    SubscriberQuery.new.select_count.should eq(0)
    Carbon::DevAdapter.delivered_emails.should be_empty
  end

  it "never echoes the submitted address back" do
    response = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "reader@example.com")

    response.body.should_not contain("reader@example.com")
  end

  it "refuses a flood from one client address" do
    # The action declares `rate_limit to: 10, within: 1.hour`; Lucky counts
    # the overage request too, so the eleventh is the last one through.
    11.times do |n|
      response = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "reader-#{n}@example.com")
      response.status.should eq(HTTP::Status.new(302))
    end

    flooded = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "flooded@example.com")

    flooded.status.should eq(HTTP::Status::TOO_MANY_REQUESTS)
    flooded.headers["Retry-After"]?.should_not be_nil
    SubscriberQuery.new.by_email("flooded@example.com").first?.should be_nil
  end

  it "bounds attempts against a single address even from one patient sender" do
    # The per-address leg of the rate limit: CrystalBits::Subscriptions
    # allows ATTEMPTS_PER_ADDRESS attempts per window, then drops them with
    # the same response a successful subscribe gets.
    CrystalBits::Subscriptions::ATTEMPTS_PER_ADDRESS.times do
      BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "victim@example.com")
    end

    dropped = BrowserClient.exec(Api::Newsletter::Subscriptions::Create, email: "victim@example.com")

    dropped.status.should eq(HTTP::Status.new(302))
    dropped.headers["Location"].should contain("/newsletter/confirmation_sent")
    SubscriberQuery.new.by_email("victim@example.com").first?.should_not be_nil
    Carbon::DevAdapter.delivered_emails.size.should eq(1)
  end
end
