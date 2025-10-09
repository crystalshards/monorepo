# GCS bucket for Redis backups
resource "google_storage_bucket" "redis_backups" {
  name          = "${var.project_id}-redis-backups"
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30 # Delete backups older than 30 days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 7
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE" # Move to cheaper storage after 7 days
    }
  }

  labels = {
    environment = "production"
    purpose     = "redis-backups"
    managed_by  = "terraform"
  }
}
