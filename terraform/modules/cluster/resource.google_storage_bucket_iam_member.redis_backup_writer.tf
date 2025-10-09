# IAM binding for Redis backup bucket
resource "google_storage_bucket_iam_member" "redis_backup_writer" {
  bucket = google_storage_bucket.redis_backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.redis_backup_sa.email}"
}
