output "service_names" {
  description = "Map of app slug to Cloud Run service name, for the load balancer's serverless NEGs. Public services only: docs-launcher is deliberately absent because it must not sit behind the load balancer"
  value       = { for app, service in google_cloud_run_v2_service.apps : app => service.name }
}

output "service_ids" {
  description = "Map of app slug to fully qualified Cloud Run service ID"
  value       = { for app, service in google_cloud_run_v2_service.apps : app => service.id }
}

output "service_uris" {
  description = "Map of app slug to the service's run.app URI. Not reachable from outside, because ingress on these four is INTERNAL_AND_CLOUD_LOAD_BALANCING; exposed for diagnostics rather than for routing"
  value       = { for app, service in google_cloud_run_v2_service.apps : app => service.uri }
}

output "service_account_emails" {
  description = "Map of app slug to the service account its revisions run as"
  value       = { for app, account in google_service_account.apps : app => account.email }
}

output "region" {
  description = "Region every service and Job runs in"
  value       = var.region
}

output "docs_launcher_service" {
  description = "Name of the private documentation build dispatcher"
  value       = google_cloud_run_v2_service.docs_launcher.name
}

output "docs_launcher_uri" {
  description = "docs-launcher's run.app URI. This is the Cloud Tasks target and the OIDC audience"
  value       = google_cloud_run_v2_service.docs_launcher.uri
}

output "docs_build_job" {
  description = "Name of the untrusted documentation build Job"
  value       = google_cloud_run_v2_job.docs_build.name
}

output "migrate_jobs" {
  description = "Map of app slug to the name of its schema migration Job"
  value       = { for app, job in google_cloud_run_v2_job.app_migrations : app => job.name }
}

output "docs_tasks_service_account_email" {
  description = "The OIDC identity Cloud Tasks presents to docs-launcher"
  value       = google_service_account.docs_tasks.email
}

output "docs_build_service_account_email" {
  description = "The untrusted build identity. Holds no IAM bindings anywhere, by design"
  value       = google_service_account.docs_build.email
}
