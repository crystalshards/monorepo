# Cloud Scheduler. The only timer in this stack, and the only thing that starts a
# shard discovery sweep. Without it the crawler is unreachable and the registry
# indexes nothing it was not handed directly.
resource "google_project_service" "cloudscheduler" {
  project = var.project_id
  service = "cloudscheduler.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
