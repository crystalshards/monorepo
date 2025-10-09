# GCP Service Account for CloudNativePG backups
resource "google_service_account" "cnpg_backup_sa" {
  account_id   = "cnpg-backup-sa"
  display_name = "CloudNativePG Backup Service Account"
  description  = "Service account for CloudNativePG to write backups to GCS"
  project      = var.project_id
}

# IAM binding for Workload Identity
resource "google_service_account_iam_member" "cnpg_backup_sa_workload_identity" {
  service_account_id = google_service_account.cnpg_backup_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[infrastructure/cnpg-backup-sa]"
}
