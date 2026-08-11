require "./object_store"

# Which buckets this app requires, and the point at which a missing one stops
# it.
#
# CrystalShards writes both: published package tarballs into PACKAGES_BUCKET,
# and the generated docs.json into DOCS_BUCKET for CrystalDocs to read back.
#
# This is per-app policy, not shared mechanism, which is why it is here and not
# in object_store.cr. A service is only given the name of a bucket it holds a
# role on, so CrystalDocs is never told PACKAGES_BUCKET and must not demand it.
# A blanket "validate everything" would refuse to boot over a variable the
# service has no business knowing.
#
# Production only. In development and test the bucket names fall back to what
# `make services` creates locally, so a contributor with no Google Cloud
# credentials can still run the app and the specs.
CrystalStorage::Buckets.require!(:docs, :packages) if LuckyEnv.production?
