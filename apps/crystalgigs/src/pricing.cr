# Commercial terms for a job posting. These are business facts, not
# configuration: they are identical in every environment and changing one is a
# product decision that belongs in version control.
module Pricing
  PRICE_CENTS = 9_900
  CURRENCY    = "usd"
  DURATION    = 60.days

  def self.price_label : String
    "$#{PRICE_CENTS // 100}"
  end

  def self.duration_days : Int32
    DURATION.total_days.to_i
  end

  def self.summary : String
    "#{price_label} for #{duration_days} days"
  end
end
