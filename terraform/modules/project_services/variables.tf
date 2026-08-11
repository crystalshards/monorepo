variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "disable_on_destroy" {
  description = <<-DESC
    Whether removing an API from this module also turns it off in the project.
    Left false on purpose. Turning an API off is project wide and takes down
    anything else already using it, and the destroy is not something you would
    ever want as a side effect of pruning a terraform file.
  DESC
  type        = bool
  default     = false
}
