locals {
  # The warming Job reads the registry, asks crystaldocs what it already holds,
  # and puts builds on the same queue a reader's request uses. It renders no
  # page and touches no bucket, so it takes neither an origin nor a bucket name.
  #
  # local.enqueuer_env is merged rather than restated. Every value in it has to
  # match what docs-launcher expects, and a second copy of the audience or the
  # tasks identity here would be one edit away from a build that enqueues
  # successfully and is then refused with a 403 nobody sees.
  warm_popular_docs_config = {
    # common_env carries GOOGLE_CLOUD_PROJECT, which `CloudTasksConfig` needs
    # to build the queue path. Merging only enqueuer_env produced a Job that
    # scanned the ranking, printed a list of what it was commissioning, raised
    # CloudTasksConfig::Missing on every single enqueue and exited 0. Every
    # value in enqueuer_env was present and correct; the one that was missing
    # was not in that table.
    env = merge(local.common_env, local.enqueuer_env, {
      # Both bounds are published for the same reason the discovery bounds are:
      # the scan is cheap and the enqueue is not, and tuning one without seeing
      # the other is how a warm run starves the builds readers are waiting on.
      WARM_SCAN_SHARDS = tostring(var.warm_scan_shards)
      WARM_MAX_BUILDS  = tostring(var.warm_max_builds)

      # The indexing pass runs first: a shard nobody has read has no versions,
      # so the documentation pass would count it as having none published and
      # skip it on every run.
      WARM_MAX_INDEXES = tostring(var.warm_max_indexes)
    })

    secret_env = {
      DATABASE_URL      = var.database_url_secret_ids["crystalshards"]
      DOCS_DATABASE_URL = var.database_url_secret_ids["crystaldocs"]
    }
  }

  warm_popular_docs_secret_accessors = {
    for secret_id in toset(values(local.warm_popular_docs_config.secret_env)) :
    "warm-popular-docs/${secret_id}" => {
      member    = "serviceAccount:${google_service_account.warm_popular_docs.email}"
      secret_id = secret_id
    }
  }
}
