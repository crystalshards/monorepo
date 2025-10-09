# GCP Service Account for Redis backups
resource "google_service_account" "redis_backup_sa" {
  account_id   = "redis-backup-sa"
  display_name = "Redis Backup Service Account"
  description  = "Service account for Redis backup jobs to write to GCS"
  project      = var.project_id
}

# IAM binding for Workload Identity
resource "google_service_account_iam_member" "redis_backup_sa_workload_identity" {
  service_account_id = google_service_account.redis_backup_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[infrastructure/redis-backup-sa]"
}
