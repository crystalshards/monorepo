require "../spec_helper"

describe SubscriptionConfirmationEmail do
  it "is addressed to the subscriber and carries a working confirmation link" do
    subscriber = SubscriberFactory.create &.email("reader@example.com").confirmation_token("abc123")

    email = SubscriptionConfirmationEmail.new(subscriber)

    email.to.should eq([Carbon::Address.new("reader@example.com")])
    email.from.should eq(Carbon::Address.new("CrystalBits", "newsletter@crystalbits.org"))
    email.subject.should contain("Confirm")
    email.text_body.should contain(Newsletter::Confirm.with("abc123").url)
  end

  it "offers a one-click unsubscribe to someone who never asked to subscribe" do
    subscriber = SubscriberFactory.create &.confirmation_token("abc123")

    email = SubscriptionConfirmationEmail.new(subscriber)

    email.headers["List-Unsubscribe"].should contain(Newsletter::Unsubscribe.with("abc123").url)
  end

  it "raises rather than send a confirmation with no token to confirm against" do
    subscriber = SubscriberFactory.create &.confirmation_token(nil)

    expect_raises(Exception, /confirmation token/) do
      SubscriptionConfirmationEmail.new(subscriber).text_body
    end
  end
end
