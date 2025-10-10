require "../spec_helper"

describe SaveSubscriber do
  it "creates subscriber with valid email" do
    operation = SaveSubscriber.new(email: "test@example.com")

    subscriber = operation.save!
    subscriber.email.should eq("test@example.com")
    subscriber.confirmed.should be_false
    subscriber.confirmation_token.should_not be_nil
  end

  it "requires email" do
    operation = SaveSubscriber.new

    operation.save.should be_false
    operation.email.errors.should contain("is required")
  end

  it "validates email format" do
    operation = SaveSubscriber.new(email: "not-an-email")

    operation.save.should be_false
    operation.email.errors.first.should contain("valid email")
  end

  it "normalizes email to lowercase" do
    operation = SaveSubscriber.new(email: "Test@EXAMPLE.COM")

    subscriber = operation.save!
    subscriber.email.should eq("test@example.com")
  end

  it "rejects duplicate email" do
    SubscriberFactory.create &.email("test@example.com")

    operation = SaveSubscriber.new(email: "test@example.com")

    operation.save.should be_false
    operation.email.errors.should contain("is already subscribed")
  end
end
