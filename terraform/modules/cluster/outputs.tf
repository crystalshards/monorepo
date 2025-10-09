output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "The endpoint of the GKE cluster"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "The CA certificate of the GKE cluster"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}

output "postgres_backup_bucket" {
  description = "PostgreSQL backup bucket name"
  value       = google_storage_bucket.postgres_backups.name
}

output "redis_backup_bucket" {
  description = "Redis backup bucket name"
  value       = google_storage_bucket.redis_backups.name
}

output "minio_backup_bucket" {
  description = "MinIO backup bucket name"
  value       = google_storage_bucket.minio_backups.name
}
