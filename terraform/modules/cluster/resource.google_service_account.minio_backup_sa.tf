# GCP Service Account for MinIO backups
resource "google_service_account" "minio_backup_sa" {
  account_id   = "minio-backup-sa"
  display_name = "MinIO Backup Service Account"
  description  = "Service account for MinIO backup jobs to write to GCS"
  project      = var.project_id
}

# IAM binding for Workload Identity
resource "google_service_account_iam_member" "minio_backup_sa_workload_identity" {
  service_account_id = google_service_account.minio_backup_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[infrastructure/minio-backup-sa]"
}
