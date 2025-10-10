class SubscriberFactory < Avram::Factory
  def initialize
    # Use a unique email with timestamp and random component
    timestamp = Time.utc.to_unix_ms
    random = Random.rand(1000000)
    email "subscriber-#{timestamp}-#{random}@example.com"
    confirmed false
    confirmation_token Random::Secure.hex(32)
    confirmed_at nil
    unsubscribed_at nil
  end
end
