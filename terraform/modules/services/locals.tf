locals {
  apps = toset(["crystalshards", "crystaldocs", "crystalgigs", "crystalbits"])

  # Every service built from a Lucky codebase, which is the four apps plus
  # docs-launcher. They all load config/** at boot and so all demand
  # SECRET_KEY_BASE and SEND_GRID_KEY, whether or not they serve a page or send
  # a mail.
  lucky_services = setunion(local.apps, toset(["docs-launcher"]))

  sendgrid_keys = {
    crystalshards   = var.crystalshards_sendgrid_key
    crystaldocs     = var.crystaldocs_sendgrid_key
    crystalgigs     = var.crystalgigs_sendgrid_key
    crystalbits     = var.crystalbits_sendgrid_key
    "docs-launcher" = var.docs_launcher_sendgrid_key
  }

  # Image references. Terraform sets a real, already pushed SHA at create time
  # and then stops caring: every service and Job below carries
  # lifecycle.ignore_changes on the image, and CI rolls subsequent tags. There
  # is deliberately no "latest" anywhere, because a floating tag makes the
  # question "what is actually serving" unanswerable from the plan.
  app_images = { for app in local.apps : app => "${var.image_repository}/${app}:${var.image_tag}" }

  docs_launcher_image = "${var.image_repository}/${var.docs_launcher_image_name}:${var.image_tag}"
  docs_build_image    = "${var.image_repository}/${var.docs_build_image_name}:${var.image_tag}"

  # Present on every application revision.
  #
  # LUCKY_ENV is load bearing beyond the obvious. It is the single switch the
  # apps use to decide production behaviour: the object store picks GCS over
  # the local filesystem on it, the job ad strip refuses to boot without its
  # endpoint on it, and the mailer, route helper and database config all branch
  # on it. A revision missing it runs as a development build that reaches for
  # localhost, which presents as a storage outage rather than as a config
  # mistake.
  common_env = {
    LUCKY_ENV                 = "production"
    GOOGLE_CLOUD_PROJECT      = var.project_id
    GOOGLE_CLOUD_REGION       = var.region
    CLOUD_SQL_CONNECTION_NAME = var.cloud_sql_connection_name
  }

  # Both crystalshards and crystaldocs put documentation builds on the queue.
  # crystaldocs is the primary producer: a reader opens a page for a version
  # with no artifact and the request commissions the build. crystalshards is
  # the secondary one, chaining a build after it indexes a new version.
  #
  # DOCS_TASKS_SERVICE_ACCOUNT is not decoration. docs-launcher grants
  # run.invoker to exactly one principal, so a task without an OIDC token minted
  # for that identity is a 403, and the symptom is documentation that never
  # appears rather than an error anybody sees.
  enqueuer_env = {
    DOCS_BUILD_QUEUE           = var.docs_build_queue_name
    DOCS_BUILD_QUEUE_LOCATION  = var.docs_build_queue_location
    DOCS_LAUNCHER_URL          = google_cloud_run_v2_service.docs_launcher.uri
    DOCS_TASKS_SERVICE_ACCOUNT = google_service_account.docs_tasks.email
  }

  # Env keys that only mean something to a request serving revision. The
  # migration Jobs below strip them: a migration never enqueues anything, and
  # handing it a launcher URL invites someone to make it do so.
  enqueue_only_env_keys = [
    "DOCS_BUILD_QUEUE",
    "DOCS_BUILD_QUEUE_LOCATION",
    "DOCS_LAUNCHER_URL",
    "DOCS_TASKS_SERVICE_ACCOUNT",
  ]

  # Per service shape and wiring. Everything that differs between the four apps
  # is visible in this one table, so the resource below stays uniform and the
  # differences cannot drift apart across four near identical blocks.
  #
  # max_instances is not a guess. Each instance holds its own connection pool,
  # and crystalshards and crystaldocs each hold two, so the product of these
  # numbers and the pool size has to fit under the instance's max_connections.
  # The arithmetic is written out on the Cloud SQL instance resource.
  app_config = {
    crystalshards = {
      max_instances = 5
      cpu           = "1"
      memory        = "512Mi"
      env = merge(local.common_env, local.enqueuer_env, {
        APP_DOMAIN      = var.app_domains["crystalshards"]
        JOB_ADS_URL     = var.job_ads_url
        DOCS_BUCKET     = var.docs_bucket_name
        PACKAGES_BUCKET = var.packages_bucket_name
      })
      secret_env = {
        DATABASE_URL    = var.database_url_secret_ids["crystalshards"]
        SECRET_KEY_BASE = google_secret_manager_secret.secret_key_base["crystalshards"].secret_id
        SEND_GRID_KEY   = google_secret_manager_secret.sendgrid_key["crystalshards"].secret_id
        # The registry records documentation build state in the crystaldocs
        # database, so this service legitimately holds two connections. It
        # connects as the crystaldocs role rather than its own, which keeps
        # table ownership where the migrations put it and avoids cross database
        # grants entirely.
        DOCS_DATABASE_URL = var.database_url_secret_ids["crystaldocs"]
      }
    }

    crystaldocs = {
      max_instances = 5
      cpu           = "1"
      memory        = "512Mi"
      env = merge(local.common_env, local.enqueuer_env, {
        APP_DOMAIN  = var.app_domains["crystaldocs"]
        JOB_ADS_URL = var.job_ads_url
        DOCS_BUCKET = var.docs_bucket_name
      })
      secret_env = {
        DATABASE_URL    = var.database_url_secret_ids["crystaldocs"]
        SECRET_KEY_BASE = google_secret_manager_secret.secret_key_base["crystaldocs"].secret_id
        SEND_GRID_KEY   = google_secret_manager_secret.sendgrid_key["crystaldocs"].secret_id
        # Mirror image of the pairing above: the docs site reads the registry.
        REGISTRY_DATABASE_URL = var.database_url_secret_ids["crystalshards"]
      }
    }

    crystalgigs = {
      max_instances = 5
      cpu           = "1"
      memory        = "512Mi"
      env = merge(local.common_env, {
        APP_DOMAIN = var.app_domains["crystalgigs"]
      })
      secret_env = {
        DATABASE_URL    = var.database_url_secret_ids["crystalgigs"]
        SECRET_KEY_BASE = google_secret_manager_secret.secret_key_base["crystalgigs"].secret_id
        SEND_GRID_KEY   = google_secret_manager_secret.sendgrid_key["crystalgigs"].secret_id
        # config/payments.cr calls exit(1) at boot in production without the
        # secret key, so this is a start up dependency and not a lazy one.
        STRIPE_SECRET_KEY      = google_secret_manager_secret.stripe_secret_key.secret_id
        STRIPE_PUBLISHABLE_KEY = google_secret_manager_secret.stripe_publishable_key.secret_id
      }
    }

    crystalbits = {
      max_instances = 5
      cpu           = "1"
      memory        = "512Mi"
      env = merge(local.common_env, {
        APP_DOMAIN  = var.app_domains["crystalbits"]
        JOB_ADS_URL = var.job_ads_url
      })
      secret_env = {
        DATABASE_URL    = var.database_url_secret_ids["crystalbits"]
        SECRET_KEY_BASE = google_secret_manager_secret.secret_key_base["crystalbits"].secret_id
        SEND_GRID_KEY   = google_secret_manager_secret.sendgrid_key["crystalbits"].secret_id
      }
    }
  }

  # Schema migration Jobs, derived from the service table rather than restated,
  # so a service that gains a boot time variable does not leave its migration
  # Job crashing on the next deploy.
  #
  # Two deliberate rewrites:
  #
  #   PORT. Cloud Run injects PORT into services and not into Jobs, and
  #   config/server.cr reads ENV["PORT"] unconditionally while tasks.cr loads
  #   the whole app. Without this the migration dies on a KeyError before it
  #   opens a connection.
  #
  #   The paired database URL. crystalshards' config demands DOCS_DATABASE_URL
  #   and crystaldocs' demands REGISTRY_DATABASE_URL at boot, but a migration
  #   Job must not be able to reach another application's database. Both are
  #   therefore pointed at the Job's OWN database. Migrations run against
  #   AppDatabase, so nothing uses the second handle. If you ever write a
  #   migration that targets DocsDatabase or the registry from here, it will
  #   write into the wrong database: split it into that app's own migration
  #   Job instead of widening this.
  migration_config = {
    for app, cfg in local.app_config : app => {
      env = merge(
        { for key, value in cfg.env : key => value if !contains(local.enqueue_only_env_keys, key) },
        { PORT = "8080" }
      )
      secret_env = {
        for env_name, secret_id in cfg.secret_env :
        env_name => contains(["DOCS_DATABASE_URL", "REGISTRY_DATABASE_URL"], env_name) ? var.database_url_secret_ids[app] : secret_id
      }
    }
  }

  # docs-launcher's environment.
  #
  # It is built from the registry codebase, so it inherits that codebase's boot
  # time demands: LUCKY_ENV, APP_DOMAIN, PORT (supplied by Cloud Run through
  # container_port), SECRET_KEY_BASE, SEND_GRID_KEY and JOB_ADS_URL. None of
  # those describe what it does, they are the price of loading config/**.
  #
  # What it actually needs is below them: the two bucket names it signs URLs
  # against, the Job it starts, and the concurrency it must not exceed.
  # DOCS_SANDBOX selects the Cloud Run Jobs sandbox implementation.
  # DOCS_SANDBOX_ALLOW_UNSAFE is deliberately absent: it exists so that building
  # without a sandbox has to be asked for by name, and production never asks.
  docs_launcher_env = merge(local.common_env, {
    APP_DOMAIN                 = var.docs_launcher_app_domain
    JOB_ADS_URL                = var.job_ads_url
    DOCS_BUCKET                = var.docs_bucket_name
    PACKAGES_BUCKET            = var.packages_bucket_name
    DOCS_BUILD_JOB             = google_cloud_run_v2_job.docs_build.name
    DOCS_BUILD_JOB_REGION      = var.region
    DOCS_BUILD_MAX_CONCURRENCY = tostring(var.docs_build_concurrency)
    DOCS_SANDBOX               = "cloudrun"
  })

  # The launcher records build outcomes itself, because it is the only identity
  # in the build path that has a database at all: docs-build has none, by
  # design. Build state lives in the crystaldocs database, reached through
  # DOCS_DATABASE_URL, and the registry connection is the codebase's own
  # AppDatabase.
  docs_launcher_secret_env = {
    DATABASE_URL      = var.database_url_secret_ids["crystalshards"]
    DOCS_DATABASE_URL = var.database_url_secret_ids["crystaldocs"]
    SECRET_KEY_BASE   = google_secret_manager_secret.secret_key_base["docs-launcher"].secret_id
    SEND_GRID_KEY     = google_secret_manager_secret.sendgrid_key["docs-launcher"].secret_id
  }

  # Flattened (identity, secret) pairs for the accessor bindings. Keyed on both
  # halves so two env vars pointing at one secret produce one binding, and
  # merged into one map so every secret grant in this stack is one resource and
  # one plan diff rather than three.
  #
  # docs-build does not appear here and must never appear here. It reads no
  # secret, because everything it may touch arrives as a signed URL.
  app_secret_accessors = merge([
    for app, cfg in local.app_config : {
      for secret_id in toset(values(cfg.secret_env)) :
      "${app}/${secret_id}" => {
        member    = "serviceAccount:${google_service_account.apps[app].email}"
        secret_id = secret_id
      }
    }
  ]...)

  migration_secret_accessors = merge([
    for app, cfg in local.migration_config : {
      for secret_id in toset(values(cfg.secret_env)) :
      "${app}-migrate/${secret_id}" => {
        member    = "serviceAccount:${google_service_account.app_migrations[app].email}"
        secret_id = secret_id
      }
    }
  ]...)

  docs_launcher_secret_accessors = {
    for secret_id in toset(values(local.docs_launcher_secret_env)) :
    "docs-launcher/${secret_id}" => {
      member    = "serviceAccount:${google_service_account.docs_launcher.email}"
      secret_id = secret_id
    }
  }

  # The application and migration grants are one resource; docs-launcher's are a
  # separate one. That split is not stylistic. local.app_config reads
  # docs-launcher's URI, so anything derived from app_config transitively
  # depends on the launcher service, and the launcher in turn has to wait for
  # its own secret grants before its first revision starts. Merging all three
  # into one resource puts the launcher on both sides of that edge and
  # terraform rejects the graph as a cycle.
  service_secret_accessors = merge(
    local.app_secret_accessors,
    local.migration_secret_accessors,
  )

  # Every identity permitted to open a connection to the Cloud SQL instance.
  # roles/cloudsql.client has no resource level binding, it is project scope
  # only, so this list is the whole answer to "what can reach the database".
  # docs-build is absent.
  cloudsql_clients = merge(
    { for app in local.apps : app => google_service_account.apps[app].email },
    { for app in local.apps : "${app}-migrate" => google_service_account.app_migrations[app].email },
    { "docs-launcher" = google_service_account.docs_launcher.email },
  )

  # The two services that put work on the docs-builds queue. crystaldocs is the
  # primary producer, commissioning a build when a reader opens a page with no
  # artifact; crystalshards chains one after indexing a new version.
  enqueuers = {
    crystalshards = google_service_account.apps["crystalshards"].email
    crystaldocs   = google_service_account.apps["crystaldocs"].email
  }

  # Storage grants, in one table so the whole object access matrix is legible.
  #
  # Two absences are the point of the design rather than omissions:
  # docs-build holds nothing, and no identity here holds a role that can delete
  # a published object. Build scratch is cleaned by the lifecycle rule on the
  # docs bucket, not by a delete permission handed to a service.
  bucket_grants = {
    "crystalshards/packages/admin" = {
      bucket = var.packages_bucket_name
      role   = "roles/storage.objectAdmin"
      member = "serviceAccount:${google_service_account.apps["crystalshards"].email}"
    }
    # BuildDocsWorker publishes <shard>/<version>/docs.json, so the registry
    # needs create and not only read on the docs bucket.
    "crystalshards/docs/create" = {
      bucket = var.docs_bucket_name
      role   = "roles/storage.objectCreator"
      member = "serviceAccount:${google_service_account.apps["crystalshards"].email}"
    }
    "crystalshards/docs/view" = {
      bucket = var.docs_bucket_name
      role   = "roles/storage.objectViewer"
      member = "serviceAccount:${google_service_account.apps["crystalshards"].email}"
    }
    "crystaldocs/docs/view" = {
      bucket = var.docs_bucket_name
      role   = "roles/storage.objectViewer"
      member = "serviceAccount:${google_service_account.apps["crystaldocs"].email}"
    }
    # The launcher signs a GET against the package source. A signed URL is
    # checked against the signer's own permissions when it is used, so this
    # read is what makes the Job's download work.
    "docs-launcher/packages/view" = {
      bucket = var.packages_bucket_name
      role   = "roles/storage.objectViewer"
      member = "serviceAccount:${google_service_account.docs_launcher.email}"
    }
    # And the matching create, which is what makes the Job's signed PUT valid.
    "docs-launcher/docs/create" = {
      bucket = var.docs_bucket_name
      role   = "roles/storage.objectCreator"
      member = "serviceAccount:${google_service_account.docs_launcher.email}"
    }
    "docs-launcher/docs/view" = {
      bucket = var.docs_bucket_name
      role   = "roles/storage.objectViewer"
      member = "serviceAccount:${google_service_account.docs_launcher.email}"
    }
  }

  # Identities that mint V4 signed URLs. With no service account key anywhere in
  # this design, signing goes through the IAM Credentials signBlob API, which
  # requires the signer to hold serviceAccountTokenCreator on ITSELF.
  #
  # docs-launcher signs the build's input and output. crystalshards signs the
  # package download endpoint's response, which has to be a signed URL because
  # uniform bucket level access and enforced public access prevention mean
  # there is no such thing as a public object here.
  url_signers = {
    "docs-launcher" = google_service_account.docs_launcher.email
    crystalshards   = google_service_account.apps["crystalshards"].email
  }
}
