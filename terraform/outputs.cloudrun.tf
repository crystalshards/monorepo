# Cloud Run stack outputs.
#
# Kept out of outputs.tf so that the GKE era outputs can be deleted, and the
# edge module's outputs added, without three changes landing in one file.

output "cloud_run_services" {
  description = "Map of app slug to Cloud Run service name. These are the four services behind the load balancer"
  value       = module.services.service_names
}

output "cloud_run_service_uris" {
  description = "Map of app slug to run.app URI. Not reachable from outside: these four services only accept load balancer traffic"
  value       = module.services.service_uris
}

output "docs_launcher_service" {
  description = "Name of the private documentation build dispatcher"
  value       = module.services.docs_launcher_service
}

output "docs_launcher_uri" {
  description = "docs-launcher run.app URI, which is both the Cloud Tasks target and the OIDC audience"
  value       = module.services.docs_launcher_uri
}

output "docs_build_job" {
  description = "Name of the untrusted documentation build Job"
  value       = module.services.docs_build_job
}

output "migrate_jobs" {
  description = "Map of app slug to the name of its schema migration Job"
  value       = module.services.migrate_jobs
}

output "discover_shards_job" {
  description = "Name of the shard discovery sweep Job"
  value       = module.services.discover_shards_job
}

output "docs_status_reconcile_job" {
  description = "Name of the idempotent documentation status reconciliation Job"
  value       = module.services.docs_status_reconcile_job
}

output "discovery_schedule" {
  description = "The cadence a bounded slice of the sweep runs on, in unix-cron"
  value       = module.scheduler.discovery_schedule
}

output "discovery_enabled_hosts" {
  description = "The git hosts actually crawled, being those whose credential holds a version. Empty means the sweep succeeds having indexed nothing, because nobody has given it a token"
  value       = module.services.discovery_enabled_hosts
}

output "discovery_credential_secret_ids" {
  description = "Map of crawler environment variable name to the Secret Manager container an operator populates to switch that host on. Container ids only, never values"
  value       = module.services.discovery_credential_secret_ids
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository ID"
  value       = module.registry.repository_id
}

output "artifact_registry_location" {
  description = "Artifact Registry location"
  value       = module.registry.location
}

output "artifact_registry_url" {
  description = "Registry path images are tagged against, without a trailing slash"
  value       = module.registry.repository_url
}

output "cloud_sql_instance" {
  description = "Cloud SQL instance name"
  value       = module.database.instance_name
}

output "cloud_sql_connection_name" {
  description = "Instance connection name, the value behind the /cloudsql/<connection_name> socket"
  value       = module.database.connection_name
}

output "docs_bucket" {
  description = "Built documentation bucket"
  value       = module.storage.docs_bucket_name
}

output "packages_bucket" {
  description = "Package artifact bucket"
  value       = module.storage.packages_bucket_name
}

output "docs_build_queue" {
  description = "Cloud Tasks queue carrying documentation build requests"
  value       = module.queue.queue_name
}
