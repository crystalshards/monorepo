variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "Region the Cloud SQL instance lives in. Same region as the Cloud Run services so the socket hop is intra region"
  type        = string
}

variable "apps" {
  description = "Application slugs. Each one gets its own database, its own login role and its own connection string secret"
  type        = set(string)
}

variable "tier" {
  description = <<-DESC
    Cloud SQL machine type. db-g1-small is a shared core tier with 1 shared
    vCPU and 1.7 GB RAM (~$26/month, down from db-custom-1-3840 at ~$50/month).
    Jason accepted the tradeoffs on 2026-09-25: no Cloud SQL SLA on shared
    core, burstable CPU, and less memory. Measured production usage over 30 days
    showed peak CPU utilization of 39.5% (p99 13.4%, p50 9.2%), peak memory
    usage of 1.47 GB with total_usage peak of 615 MB (p99 599 MB, p50 500 MB),
    and peak backends of 16 (p99 8, p50 2), fitting safely within 1.7 GB.
  DESC
  type        = string
  default     = "db-g1-small"
}

variable "max_connections" {
  description = <<-DESC
    Server side connection ceiling. This has to be reasoned about together with
    per service max_instances and the max_pool_size baked into each connection
    string, because Cloud Run multiplies them: every instance of every service
    holds its own pool. The arithmetic the current numbers produce is in the
    comment on resource.google_sql_database_instance.crystal_postgres.
  DESC
  type        = number
  default     = 90
}

variable "connection_pool_size" {
  description = "max_pool_size written into every connection string. crystal-db defaults this to 0, meaning unlimited, which is exactly how a scale to zero service exhausts a small Postgres the moment traffic arrives"
  type        = number
  default     = 2
}

variable "backup_retained_count" {
  description = "How many automated backups to keep"
  type        = number
  default     = 14
}
