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
    Cloud SQL machine type. db-custom-1-3840 is one dedicated vCPU and 3.75 GB,
    the smallest tier that is not shared core. The shared core tiers below it,
    db-f1-micro and db-g1-small, are excluded from the Cloud SQL SLA and their
    CPU is burstable rather than reserved, which is the wrong failure mode for
    the one stateful component four services depend on.
  DESC
  type        = string
  default     = "db-custom-1-3840"
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
  default     = 200
}

variable "connection_pool_size" {
  description = "max_pool_size written into every connection string. crystal-db defaults this to 0, meaning unlimited, which is exactly how a scale to zero service exhausts a small Postgres the moment traffic arrives"
  type        = number
  default     = 5
}

variable "backup_retained_count" {
  description = "How many automated backups to keep"
  type        = number
  default     = 14
}
