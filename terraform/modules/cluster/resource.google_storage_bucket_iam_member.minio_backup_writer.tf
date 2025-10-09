# IAM binding for MinIO backup bucket
resource "google_storage_bucket_iam_member" "minio_backup_writer" {
  bucket = google_storage_bucket.minio_backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.minio_backup_sa.email}"
}
