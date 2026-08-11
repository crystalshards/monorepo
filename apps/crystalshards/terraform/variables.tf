variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy (git commit SHA, e.g., 'sha-abc123')"
  type        = string
  # No default - must be explicitly set to prevent accidental 'latest' deployments
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

# ---------------------------------------------------------------------------
# Docs build sandbox (untrusted `crystal docs` execution)
# ---------------------------------------------------------------------------

variable "docs_sandbox_image" {
  description = "Container image used for untrusted documentation builds in the docs-sandbox namespace"
  type        = string
  # Must track the toolchain the platform builds with. On an older compiler a
  # shard using newer standard library types fails to document for a reason
  # that has nothing to do with the shard.
  default = "crystallang/crystal:1.21.0-alpine"
}

variable "docs_sandbox_timeout_seconds" {
  description = "Wall clock limit in seconds for a single documentation build Job"
  type        = number
  default     = 900
}

variable "docs_sandbox_memory" {
  description = "Memory limit applied to each documentation build container (also the LimitRange default limit)"
  type        = string
  default     = "2Gi"
}

variable "docs_sandbox_cpus" {
  description = "CPU limit applied to each documentation build container (also the LimitRange default limit)"
  type        = string
  default     = "2"
}

variable "docs_sandbox_pids" {
  description = "Maximum number of processes (pids) allowed in a documentation build pod"
  type        = number
  default     = 256
}

variable "docs_sandbox_runtime_class" {
  description = "RuntimeClass name for docs build pods (for example gvisor, when a gVisor RuntimeClass is installed). Null or empty uses the cluster default runtime. Surfaced to the worker as DOCS_SANDBOX_RUNTIME_CLASS."
  type        = string
  default     = null
}

variable "docs_sandbox_scratch_prefix" {
  description = "MinIO prefix (in the docs bucket) under which source tarballs are staged for builds"
  type        = string
  default     = "build-scratch"
}

# Namespace-level quota bounds (total across all build Jobs)
variable "docs_sandbox_quota_max_pods" {
  description = "Maximum total pods (and batch Jobs) in the docs-sandbox namespace"
  type        = string
  default     = "20"
}

variable "docs_sandbox_quota_requests_cpu" {
  description = "Total requested CPU allowed across the docs-sandbox namespace"
  type        = string
  default     = "10"
}

variable "docs_sandbox_quota_requests_memory" {
  description = "Total requested memory allowed across the docs-sandbox namespace"
  type        = string
  default     = "20Gi"
}

variable "docs_sandbox_quota_limits_cpu" {
  description = "Total CPU limits allowed across the docs-sandbox namespace"
  type        = string
  default     = "20"
}

variable "docs_sandbox_quota_limits_memory" {
  description = "Total memory limits allowed across the docs-sandbox namespace"
  type        = string
  default     = "40Gi"
}

# Per-container LimitRange bounds for build pods
variable "docs_sandbox_default_request_cpu" {
  description = "Default CPU request for a build container that omits requests"
  type        = string
  default     = "250m"
}

variable "docs_sandbox_default_request_memory" {
  description = "Default memory request for a build container that omits requests"
  type        = string
  default     = "512Mi"
}

variable "docs_sandbox_max_cpu" {
  description = "Maximum CPU a single build container may request or limit"
  type        = string
  default     = "4"
}

variable "docs_sandbox_max_memory" {
  description = "Maximum memory a single build container may request or limit"
  type        = string
  default     = "8Gi"
}

# The build Jobs' storage credentials are derived from the same MinIO data
# source the application secret uses, in
# resource.kubernetes_secret.docs_sandbox_storage.tf, rather than being
# threaded through variables. One source of truth, and no second set of
# credentials to keep in step.

variable "docs_sandbox_secret_name" {
  description = "Name of the storage credential Secret in the docs-sandbox namespace"
  type        = string
  default     = "docs-sandbox-storage"
}
