# Services Module
# The four public Cloud Run services, the private docs-launcher, the untrusted
# docs-build Job, the four schema migration Jobs, and all of their identities
# and IAM.
module "services" {
  source = "./modules/services"

  project_id = var.project_id
  region     = var.region

  image_repository = module.registry.repository_url
  image_tag        = var.image_tag

  cloud_sql_connection_name = module.database.connection_name
  database_url_secret_ids   = module.database.database_url_secret_ids

  docs_bucket_name     = module.storage.docs_bucket_name
  packages_bucket_name = module.storage.packages_bucket_name

  docs_build_queue_name     = module.queue.queue_name
  docs_build_queue_location = module.queue.location
  docs_build_concurrency    = module.queue.max_concurrent_dispatches

  # Every hostname this module sees is derived from local.sites, the one place
  # the four domains are written. The edge module and the DNS module read the
  # same map, so an app cannot be told it lives at a hostname the load balancer
  # does not serve.
  app_domains              = { for slug, site in local.sites : slug => "https://${site.apex}" }
  job_ads_url              = "https://${local.sites["crystalgigs"].apex}/api/ads"
  docs_launcher_app_domain = "https://${local.sites["crystalshards"].apex}"

  depends_on = [module.project_services]
}
