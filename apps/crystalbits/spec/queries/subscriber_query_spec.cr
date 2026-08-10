require "../spec_helper"

describe SubscriberQuery do
  describe "#active" do
    it "returns confirmed and not unsubscribed subscribers" do
      active = SubscriberFactory.create do |s|
        s.confirmed(true)
        s.unsubscribed_at(nil)
      end
      not_confirmed = SubscriberFactory.create do |s|
        s.confirmed(false)
        s.unsubscribed_at(nil)
      end
      unsubscribed = SubscriberFactory.create do |s|
        s.confirmed(true)
        s.unsubscribed_at(Time.utc - 1.day)
      end

      results = SubscriberQuery.new.active.to_a

      results.should contain(active)
      results.should_not contain(not_confirmed)
      results.should_not contain(unsubscribed)
    end
  end

  describe "#pending_confirmation" do
    it "returns unconfirmed and not unsubscribed subscribers" do
      pending = SubscriberFactory.create do |s|
        s.confirmed(false)
        s.unsubscribed_at(nil)
      end
      confirmed = SubscriberFactory.create do |s|
        s.confirmed(true)
        s.unsubscribed_at(nil)
      end
      unsubscribed = SubscriberFactory.create do |s|
        s.confirmed(false)
        s.unsubscribed_at(Time.utc - 1.day)
      end

      results = SubscriberQuery.new.pending_confirmation.to_a

      results.should contain(pending)
      results.should_not contain(confirmed)
      results.should_not contain(unsubscribed)
    end
  end

  describe "#by_email" do
    it "finds subscriber by email" do
      subscriber = SubscriberFactory.create &.email("test@example.com")
      other = SubscriberFactory.create &.email("other@example.com")

      result = SubscriberQuery.new.by_email("test@example.com").first

      result.id.should eq(subscriber.id)
    end

    it "is case sensitive" do
      SubscriberFactory.create &.email("test@example.com")

      expect_raises(Avram::RecordNotFoundError) do
        SubscriberQuery.new.by_email("TEST@EXAMPLE.COM").first
      end
    end
  end

  describe "#by_confirmation_token" do
    it "finds subscriber by confirmation token" do
      subscriber = SubscriberFactory.create &.confirmation_token("unique-token-123")
      other = SubscriberFactory.create &.confirmation_token("different-token-456")

      result = SubscriberQuery.new.by_confirmation_token("unique-token-123").first

      result.id.should eq(subscriber.id)
    end

    it "returns nil for non-existent token" do
      SubscriberFactory.create &.confirmation_token("existing-token")

      result = SubscriberQuery.new.by_confirmation_token("non-existent").first?

      result.should be_nil
    end
  end

  describe "chaining" do
    it "can chain active with by_email" do
      active = SubscriberFactory.create do |s|
        s.email("active@example.com")
        s.confirmed(true)
        s.unsubscribed_at(nil)
      end
      inactive = SubscriberFactory.create do |s|
        s.email("inactive@example.com")
        s.confirmed(false)
        s.unsubscribed_at(nil)
      end

      result = SubscriberQuery.new.active.by_email("active@example.com").first
      result.id.should eq(active.id)

      expect_raises(Avram::RecordNotFoundError) do
        SubscriberQuery.new.active.by_email("inactive@example.com").first
      end
    end
  end
end
