variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
}

variable "postgres_backup_bucket" {
  description = "GCS bucket for PostgreSQL backups"
  type        = string
}

variable "redis_backup_bucket" {
  description = "GCS bucket for Redis backups"
  type        = string
}

variable "minio_backup_bucket" {
  description = "GCS bucket for MinIO backups"
  type        = string
}
