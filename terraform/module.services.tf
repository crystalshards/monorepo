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
  docs_build_queue_id       = module.queue.queue_id
  docs_build_queue_location = module.queue.location
  docs_build_concurrency    = module.queue.max_concurrent_dispatches

  crystalshards_sendgrid_key = var.crystalshards_sendgrid_key
  crystaldocs_sendgrid_key   = var.crystaldocs_sendgrid_key
  crystalgigs_sendgrid_key   = var.crystalgigs_sendgrid_key
  crystalbits_sendgrid_key   = var.crystalbits_sendgrid_key
  docs_launcher_sendgrid_key = var.docs_launcher_sendgrid_key

  crystalgigs_stripe_secret_key      = var.crystalgigs_stripe_secret_key
  crystalgigs_stripe_publishable_key = var.crystalgigs_stripe_publishable_key

  depends_on = [module.project_services]
}
