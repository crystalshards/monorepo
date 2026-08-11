# Permission to put a documentation build on the queue. Bound on the queue, not
# the project, so nothing else in the stack can enqueue.
resource "google_cloud_tasks_queue_iam_member" "enqueuers" {
  for_each = local.enqueuers

  project = var.project_id
  # google_cloud_tasks_queue_iam_member takes the location and short name
  # rather than the fully qualified id.
  location = var.docs_build_queue_location
  name     = var.docs_build_queue_name
  role     = "roles/cloudtasks.enqueuer"
  member   = "serviceAccount:${each.value}"
}
