# Services Module
# The four public Cloud Run services, the private docs-launcher, the untrusted
# docs-build Job, the four schema migration Jobs, the shard discovery sweep Job,
# and all of their identities and IAM.
module "services" {
  source = "./modules/services"

  project_id = var.project_id
  region     = var.region

  image_repository = module.registry.repository_url
  image_tag        = var.image_tag

  cloud_sql_connection_name = module.database.connection_name
  database_url_secret_ids   = module.database.database_url_secret_ids

  # Which senders may reference their Resend secret. Empty means both serve with
  # mail raising on send. CI passes the slugs it populated.
  mail_enabled_apps = var.mail_enabled_apps

  # Which git hosts may reference their discovery credential. Empty means the
  # sweep runs, reports every host as skipped naming the variable that would
  # enable it, and indexes nothing. CI passes the hosts it populated.
  discovery_enabled_hosts = var.discovery_enabled_hosts

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
