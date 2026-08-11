# Built documentation artifacts, written by the docs-build Job through a signed
# PUT and read by crystaldocs.
#
# Lifecycle reasoning. Documentation is regenerable: every object here can be
# rebuilt from the shard source in the packages bucket by rerunning
# `crystal docs`. That is what makes ageing it out safe, and it is also why
# nothing in these rules deletes a live object. The two Delete rules are both
# gated on with_state = "ARCHIVED", so they can only ever reach a generation
# that a newer write already superseded. The version a request would actually
# be served is untouchable by any rule in this bucket.
#
# force_destroy is true here and false on the packages bucket, and that
# asymmetry is deliberate. Versioning plus force_destroy = false means an
# ordinary destroy fails partway through on a non empty bucket, which is a bad
# trade for a cache that can be regenerated but a good one for anything that
# cannot.
resource "google_storage_bucket" "docs" {
  project  = var.project_id
  name     = "crystalshards-docs"
  location = var.region

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  versioning {
    enabled = true
  }

  # Prune superseded generations once enough newer ones exist.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      with_state         = "ARCHIVED"
      num_newer_versions = var.docs_noncurrent_versions_kept
    }
  }

  # Prune superseded generations on age, for objects that are rewritten rarely
  # enough that the count rule above would keep them forever.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      with_state                 = "ARCHIVED"
      days_since_noncurrent_time = var.docs_noncurrent_retention_days
    }
  }

  # Cool live objects down as they age. No deletion, only storage class, so a
  # request for five year old docs still succeeds, just off cheaper media.
  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      with_state            = "LIVE"
      age                   = var.docs_nearline_after_days
      matches_storage_class = ["STANDARD"]
    }
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
    condition {
      with_state            = "LIVE"
      age                   = var.docs_coldline_after_days
      matches_storage_class = ["NEARLINE"]
    }
  }

  # Per build scratch, under the build-scratch/ prefix.
  #
  # docs-launcher stages a build's working objects here and clears them when the
  # execution finishes, but an execution that dies hard leaks them, and no
  # identity in this stack holds a delete permission on this bucket to clean up
  # after the fact. This rule is the cleanup, and it is why the launcher does
  # not need one.
  #
  # matches_prefix keeps it away from published documentation: an object at
  # <shard>/<version>/docs.json does not match build-scratch/ and cannot be
  # caught by this rule regardless of age.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      with_state     = "ANY"
      age            = var.docs_scratch_retention_days
      matches_prefix = [var.docs_scratch_prefix]
    }
  }

  # A docs build that dies mid upload otherwise leaves parts that are billed
  # and invisible.
  lifecycle_rule {
    action {
      type = "AbortIncompleteMultipartUpload"
    }
    condition {
      age = 7
    }
  }

  labels = {
    environment = "production"
    managed_by  = "terraform"
  }
}
