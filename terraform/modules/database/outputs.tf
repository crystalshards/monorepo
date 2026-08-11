output "instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.crystal_postgres.name
}

output "connection_name" {
  description = "Instance connection name, the project:region:instance form Cloud Run mounts as /cloudsql/<connection_name>"
  value       = google_sql_database_instance.crystal_postgres.connection_name
}

output "database_url_secret_ids" {
  description = "Map of app slug to the Secret Manager secret_id holding that database's connection string"
  value       = { for app, secret in google_secret_manager_secret.database_url : app => secret.secret_id }
}

output "database_url_secret_names" {
  description = "Map of app slug to the fully qualified secret name, for IAM bindings"
  value       = { for app, secret in google_secret_manager_secret.database_url : app => secret.name }
}

output "database_names" {
  description = "Map of app slug to database name"
  value       = { for app, database in google_sql_database.apps : app => database.name }
}
