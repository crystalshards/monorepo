require "./object_store"

# Which buckets this app requires, and the point at which a missing one stops
# it.
#
# CrystalDocs only ever reads built documentation, so DOCS_BUCKET is the whole
# list. It holds no role on the packages bucket and is never given its name,
# so demanding PACKAGES_BUCKET here would refuse to boot over a variable this
# service has no business knowing.
#
# This is per-app policy, not shared mechanism, which is why it is here and not
# in object_store.cr.
#
# Production only. In development and test the bucket name falls back to what
# `make services` creates locally, so a contributor with no Google Cloud
# credentials can still run the app and the specs.
CrystalStorage::Buckets.require!(:docs) if LuckyEnv.production?
