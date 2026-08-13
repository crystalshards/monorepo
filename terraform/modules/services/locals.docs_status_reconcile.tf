locals {
  # The reconciliation binary loads only the two database configs and the
  # object store. Keeping this separate from app_config prevents a future web
  # service boot variable from becoming a Job requirement.
  docs_status_reconcile_config = {
    env = {
      LUCKY_ENV   = "production"
      DOCS_BUCKET = var.docs_bucket_name
    }
    secret_env = {
      DATABASE_URL      = var.database_url_secret_ids["crystalshards"]
      DOCS_DATABASE_URL = var.database_url_secret_ids["crystaldocs"]
    }
  }

  docs_status_reconcile_secret_accessors = {
    for secret_id in toset(values(local.docs_status_reconcile_config.secret_env)) :
    "docs-status-reconcile/${secret_id}" => {
      member    = "serviceAccount:${google_service_account.docs_status_reconcile.email}"
      secret_id = secret_id
    }
  }
}
