# IAM binding for PostgreSQL backup bucket
resource "google_storage_bucket_iam_member" "postgres_backup_writer" {
  bucket = google_storage_bucket.postgres_backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cnpg_backup_sa.email}"
}
