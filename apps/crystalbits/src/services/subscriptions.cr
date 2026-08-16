module CrystalBits
  # The one newsletter signup flow. The browser form on this site
  # (Newsletter::Subscribe) and the cross-origin API action
  # (Api::Newsletter::Subscriptions::Create) both land here, so there is a
  # single subscriber store, a single validation path and a single
  # confirmation send.
  #
  # Two rules shape everything below:
  #
  # 1. The response never reveals whether an address is new, already
  #    subscribed, or already confirmed. Every non-junk submission ends in the
  #    same "check your email" outcome, so the flow is not a
  #    subscription-state oracle.
  # 2. An open endpoint that sends mail is a spam relay the moment it sends
  #    without bound, so sends are bounded on two axes: per client address in
  #    the API action (Lucky::RateLimit, see docs/RATE_LIMITING.md), and per
  #    subscribed address here.
  module Subscriptions
    # The floor between two confirmation emails to the same address: at most
    # one per hour, no matter how often the form is submitted. Re-submitting
    # an unconfirmed address is the "I did not get the email" case, so the
    # confirmation is re-sent, just never in a stream.
    CONFIRMATION_RESEND_INTERVAL = 1.hour

    # How many subscribe attempts one address may drive per window before
    # further attempts are dropped without effect. This is the leg that keeps
    # a flood from many different client addresses (where the per-IP limit
    # cannot see it) from turning into unbounded database writes for a single
    # victim address.
    ATTEMPTS_PER_ADDRESS        = 5
    ATTEMPTS_PER_ADDRESS_WINDOW = 1.hour

    enum Result
      # A new subscriber was created and a confirmation email was sent.
      Subscribed
      # The address was already known. For an unconfirmed address the
      # confirmation is re-sent subject to CONFIRMATION_RESEND_INTERVAL.
      AlreadySubscribed
      # The submitted value is not an email address. Nothing was created and
      # nothing was sent.
      Invalid
      # The address has exhausted ATTEMPTS_PER_ADDRESS. The attempt was
      # dropped with no other effect.
      Throttled
    end

    def self.subscribe(raw_email : String?) : Result
      email = raw_email.to_s.strip.downcase
      return Result::Invalid if junk?(email)
      return Result::Throttled if attempts_exceeded?(email)

      if subscriber = SubscriberQuery.new.by_email(email).first?
        # A confirmed address has nothing to confirm, so it gets no mail; the
        # caller cannot tell the difference.
        send_confirmation(subscriber) unless subscriber.confirmed
        return Result::AlreadySubscribed
      end

      create(email)
    end

    # Obvious junk only. The strict format check stays in SaveSubscriber, so
    # anything borderline is created-or-refused by the operation, never by a
    # second rule that could disagree with it. Over 254 chars is never an
    # address (RFC 5321), just a payload.
    private def self.junk?(email : String) : Bool
      email.blank? || email.size > 254 || !email.includes?('@') || email.matches?(/\s/)
    end

    private def self.create(email : String) : Result
      SaveSubscriber.create(email: email) do |operation, subscriber|
        if subscriber
          send_confirmation(subscriber)
          Result::Subscribed
          # The only validation left that can fail after the checks above is
          # uniqueness, which means a concurrent subscribe for the same address
          # won the race. From the outside that is indistinguishable from the
          # address having been there all along.
        elsif operation.email.errors.includes?("is already subscribed")
          Result::AlreadySubscribed
        else
          Result::Invalid
        end
      end
    end

    # The per-address attempt counter, in the same cache store the
    # action-level rate limit uses. Every attempt spends budget, including
    # throttled ones, so hammering an address keeps it throttled for the full
    # window rather than letting it back in on every request.
    private def self.attempts_exceeded?(email : String) : Bool
      cache = LuckyCache.settings.storage
      key = "ratelimit:newsletter:subscriptions:email:#{email}"
      attempts = cache.fetch(key, as: Int32, expires_in: ATTEMPTS_PER_ADDRESS_WINDOW) { 0 }
      cache.write(key, expires_in: ATTEMPTS_PER_ADDRESS_WINDOW) { attempts + 1 }
      attempts >= ATTEMPTS_PER_ADDRESS
    end

    # One confirmation email per address per CONFIRMATION_RESEND_INTERVAL.
    # The marker lives in the cache store rather than on the record, so the
    # floor expires by itself and the subscriber row stays a record of fact,
    # not of mail timing.
    private def self.send_confirmation(subscriber : Subscriber) : Nil
      cache = LuckyCache.settings.storage
      key = "newsletter:confirmation-sent:#{subscriber.email}"
      return if cache.read(key)

      SubscriptionConfirmationEmail.new(subscriber).deliver_later
      cache.write(key, expires_in: CONFIRMATION_RESEND_INTERVAL) { true }
    end
  end
end
