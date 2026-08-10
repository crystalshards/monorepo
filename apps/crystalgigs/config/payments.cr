require "stripe"

# Payments run against Stripe whenever credentials are configured.
#
# Production ALWAYS requires them: a deploy missing STRIPE_SECRET_KEY fails at
# boot rather than quietly failing to take money. There is deliberately no
# fallback to a placeholder key.
#
# Outside production, payments are disabled unless a key is supplied, so specs
# and a fresh clone run with no configuration at all. Setting
# PAYMENTS_DISABLED=true forces them off in any environment.
module Payments
  class_getter? disabled : Bool = begin
    if ENV["PAYMENTS_DISABLED"]? == "true"
      true
    else
      !LuckyEnv.production? && ENV["STRIPE_SECRET_KEY"]?.nil?
    end
  end

  def self.publishable_key : String
    ENV["STRIPE_PUBLISHABLE_KEY"]? ||
      raise "Missing STRIPE_PUBLISHABLE_KEY. Set it, or set PAYMENTS_DISABLED=true to run without payment processing."
  end
end

unless Payments.disabled?
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]? || begin
    puts "Missing STRIPE_SECRET_KEY. Set STRIPE_SECRET_KEY, or set PAYMENTS_DISABLED=true to run without payment processing.".colorize.red
    exit(1)
  end
end
