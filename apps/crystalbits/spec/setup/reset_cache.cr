# The rate limit and confirmation-send counters persist in the configured
# cache store, so without this every example would inherit the requests the
# examples before it made.
Spec.before_each do
  LuckyCache.settings.storage.flush
end
