variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "Region both buckets live in. Same region as Cloud Run so reads and writes are not cross region"
  type        = string
}

variable "docs_noncurrent_versions_kept" {
  description = "How many superseded generations of a documentation object survive before the oldest is deleted"
  type        = number
  default     = 2
}

variable "docs_noncurrent_retention_days" {
  description = "How long a superseded documentation generation survives regardless of how many newer ones exist"
  type        = number
  default     = 30
}

variable "docs_nearline_after_days" {
  description = "Age at which live documentation objects move to Nearline. Docs for an old shard version are written once and then almost never read again"
  type        = number
  default     = 30
}

variable "docs_coldline_after_days" {
  description = "Age at which live documentation objects move to Coldline"
  type        = number
  default     = 180
}

variable "packages_noncurrent_retention_days" {
  description = "How long a superseded package object survives. Only ever applies to generations that something replaced, never to the version currently being served"
  type        = number
  default     = 90
}

variable "docs_scratch_prefix" {
  description = "Object prefix docs-launcher stages per build scratch under. Anything below it is disposable by definition"
  type        = string
  default     = "build-scratch/"
}

variable "docs_scratch_retention_days" {
  description = "How long leaked build scratch survives. Long enough to inspect a failed build, short enough that a crash loop does not accumulate"
  type        = number
  default     = 1
}
