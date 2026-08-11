# Package artifacts. Read by the docs-build Job through a signed GET.
#
# No rule in this bucket deletes or downgrades a live object. A package's
# current version is the input every future documentation build depends on, and
# unlike the docs bucket there is nothing to regenerate it from. The only
# Delete rule is gated on with_state = "ARCHIVED", so it can only reach a
# generation that a newer upload already replaced.
#
# force_destroy stays false. A destroy that stops on a non empty bucket is the
# correct outcome for content that cannot be rebuilt.
resource "google_storage_bucket" "packages" {
  project  = var.project_id
  name     = "crystalshards-packages"
  location = var.region

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      with_state                 = "ARCHIVED"
      days_since_noncurrent_time = var.packages_noncurrent_retention_days
    }
  }

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
