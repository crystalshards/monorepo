output "docs_bucket_name" {
  description = "Name of the built documentation bucket"
  value       = google_storage_bucket.docs.name
}

output "packages_bucket_name" {
  description = "Name of the package artifact bucket"
  value       = google_storage_bucket.packages.name
}
