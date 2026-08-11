output "queue_name" {
  description = "Short queue name, the value wired into DOCS_BUILD_QUEUE"
  value       = google_cloud_tasks_queue.docs_builds.name
}

output "queue_id" {
  description = "Fully qualified queue ID, for IAM bindings"
  value       = google_cloud_tasks_queue.docs_builds.id
}

output "location" {
  description = "Queue location"
  value       = google_cloud_tasks_queue.docs_builds.location
}

output "max_concurrent_dispatches" {
  description = "The global build concurrency cap, exported so the services module can pin docs-launcher max_instances to the same number instead of restating it"
  value       = var.max_concurrent_dispatches
}
