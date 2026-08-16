# The store behind Lucky::RateLimit and the per-address bounds in
# CrystalBits::Subscriptions.
#
# LuckyCache's default NullStore discards every write, which is why
# docs/RATE_LIMITING.md used to read "declared but not enforced" for every
# app in this repo: the counters never accumulated. A process-local memory
# store is enough here. The limits exist to stop a spam relay, not to meter
# billing, and a sender rotating past a per-instance counter still meets the
# per-address confirmation floor wherever it lands next.
LuckyCache.configure do |settings|
  settings.storage = LuckyCache::MemoryStore.new
end
