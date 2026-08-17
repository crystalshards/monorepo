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

  # All four sites are registered in Search Console as domain properties, so
  # the property name is the apex under the sc-domain scheme. Derived from the
  # same local.sites the origins above come from, so a site cannot be told to
  # ask Google about a hostname it does not serve.
  #
  # A property here is only half the wiring. The other half is this repo's
  # service account for that app being a user on that property, which lives in
  # Search Console and not in any state file:
  #   crystalshards@<project>.iam.gserviceaccount.com -> sc-domain:crystalshards.org
  #   crystaldocs@<project>.iam.gserviceaccount.com   -> sc-domain:crystaldocs.org
  #   crystalgigs@<project>.iam.gserviceaccount.com   -> sc-domain:crystalgigs.com
  #   crystalbits@<project>.iam.gserviceaccount.com   -> sc-domain:crystalbits.org
  # all added as Restricted users. Revoke there and the fetch 403s naming the
  # account, which is the state the stats page reports rather than hides.
  search_console_properties = { for slug, site in local.sites : slug => "sc-domain:${site.apex}" }

  depends_on = [module.project_services]
}
