require "stripe"

# Payments run against Stripe in every environment. Local development and CI
# have no Stripe credentials, so they must opt out explicitly by setting
# PAYMENTS_DISABLED=true. There is deliberately no silent fallback to a
# placeholder key: a misconfigured production deploy fails at boot instead of
# quietly failing to take money.
module Payments
  class_getter? disabled : Bool = ENV["PAYMENTS_DISABLED"]? == "true"

  def self.publishable_key : String
    ENV["STRIPE_PUBLISHABLE_KEY"]? || raise_missing_key("STRIPE_PUBLISHABLE_KEY")
  end

  def self.raise_missing_key(name : String) : NoReturn
    raise "Missing #{name}. Set it, or set PAYMENTS_DISABLED=true to run without payment processing."
  end
end

unless Payments.disabled?
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]? || begin
    puts "Missing STRIPE_SECRET_KEY. Set STRIPE_SECRET_KEY, or set PAYMENTS_DISABLED=true to run without payment processing.".colorize.red
    exit(1)
  end
end
