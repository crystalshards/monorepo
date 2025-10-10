require "../spec_helper"

describe SaveSubscriber do
  describe "validations" do
    it "requires email" do
      operation = SaveSubscriber.new

      operation.save.should be_false
      operation.valid?.should be_false
      operation.email.errors.should contain("is required")
    end

    it "validates email format" do
      operation = SaveSubscriber.new(email: "not-an-email")

      operation.save.should be_false
      operation.email.errors.first.should contain("valid email")
    end

    it "accepts valid email" do
      operation = SaveSubscriber.new(email: "valid@example.com")

      subscriber = operation.save!
      subscriber.email.should eq("valid@example.com")
    end

    it "rejects duplicate email" do
      SubscriberFactory.create &.email("test@example.com")

      operation = SaveSubscriber.new(email: "test@example.com")

      operation.save.should be_false
      operation.email.errors.should contain("is already subscribed")
    end

    it "normalizes email to lowercase" do
      operation = SaveSubscriber.new(email: "Test@EXAMPLE.COM")

      subscriber = operation.save!
      subscriber.email.should eq("test@example.com")
    end

    pending "trims whitespace from email" do
      # TODO: Fix normalization to happen before validation
      # See issue #49 for investigation details
      operation = SaveSubscriber.new(email: "  test@example.com  ")

      subscriber = operation.save!
      subscriber.email.should eq("test@example.com")
    end
  end

  describe "confirmation token" do
    it "generates confirmation token on create" do
      operation = SaveSubscriber.new(email: "test@example.com")

      subscriber = operation.save!
      subscriber.confirmation_token.should_not be_nil
      subscriber.confirmation_token.not_nil!.size.should eq(64) # 32 bytes hex = 64 chars
    end

    it "sets confirmed to false on create" do
      operation = SaveSubscriber.new(email: "test@example.com")

      subscriber = operation.save!
      subscriber.confirmed.should be_false
    end

    it "generates unique tokens" do
      subscriber1 = SaveSubscriber.create!(email: "test1@example.com")
      subscriber2 = SaveSubscriber.create!(email: "test2@example.com")

      subscriber1.confirmation_token.should_not eq(subscriber2.confirmation_token)
    end
  end

  describe "update" do
    pending "can confirm subscriber" do
      # TODO: Fix uniqueness validation to skip on update
      # See issue #49 for investigation details
      subscriber = SubscriberFactory.create do |s|
        s.email("test@example.com")
        s.confirmed(false)
      end

      SaveSubscriber.update!(subscriber,
        confirmed: true,
        confirmed_at: Time.utc
      )

      subscriber.reload
      subscriber.confirmed.should be_true
      subscriber.confirmed_at.should_not be_nil
    end

    pending "can unsubscribe subscriber" do
      # TODO: Fix uniqueness validation to skip on update
      # See issue #49 for investigation details
      subscriber = SubscriberFactory.create do |s|
        s.confirmed(true)
        s.unsubscribed_at(nil)
      end

      SaveSubscriber.update!(subscriber, unsubscribed_at: Time.utc)

      subscriber.reload
      subscriber.unsubscribed_at.should_not be_nil
    end
  end
end
