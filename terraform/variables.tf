variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  default     = "crystalshards-cluster"
}

variable "node_count" {
  description = "Initial number of nodes in the cluster"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "The machine type for cluster nodes"
  type        = string
  default     = "e2-standard-4"
}

variable "disk_size_gb" {
  description = "Disk size for cluster nodes in GB"
  type        = number
  default     = 50
}

variable "enable_autopilot" {
  description = "Enable GKE Autopilot for cost optimization"
  type        = bool
  default     = false
}

variable "preemptible" {
  description = "Use preemptible nodes for cost savings"
  type        = bool
  default     = true
}