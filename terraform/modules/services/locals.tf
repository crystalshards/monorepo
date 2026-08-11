locals {
  apps = toset(["crystalshards", "crystaldocs", "crystalgigs", "crystalbits"])

  # Every service built from a Lucky codebase, which is the four apps plus
  # docs-launcher. They all load config/** at boot and so all demand
  # SECRET_KEY_BASE, whether or not they serve a page or send a mail. A mail
  # credential is deliberately not on that list: only the two senders below ask
  # for one.
  lucky_services = setunion(local.apps, toset(["docs-launcher"]))

  # The services that actually send mail, and therefore the only ones that get a
  # RESEND_API_KEY or a secret to hold it.
  #
  # crystalshards, crystaldocs and docs-launcher are absent because they send
  # nothing: config/email.cr in those apps selects a non-sending adapter and asks
  # for no credential. They used to hard-exit at boot without a mail key, which
  # meant a package registry refusing to serve a page over a credential it never
  # used, and it is what made the sentinel string "unused" look necessary. With
  # the app fixed, the right answer here is not a placeholder value but no secret
  # at all.
  mail_senders = toset(["crystalgigs", "crystalbits"])

  # Of the senders, the ones whose Resend secret CI has actually put a version
  # into. Only these get RESEND_API_KEY on their revision.
  #
  # A Cloud Run revision that references a secret with no versions never reaches
  # Ready, so wiring this unconditionally would keep crystalgigs.com and
  # crystalbits.org down for as long as the key is missing. Serving is the
  # primary function and mail is a feature: the site serves without a key and the
  # adapter raises on an actual send attempt naming RESEND_API_KEY.
  #
  # The intersection is deliberate rather than a straight read of the variable.
  # No value CI can pass can wire a mail secret into crystalshards, crystaldocs
  # or docs-launcher, so the three way split is enforced here rather than by CI
  # passing the right list.
  mail_enabled = setintersection(local.mail_senders, var.mail_enabled_apps)

  # RESEND_API_KEY for the enabled senders, nothing for the rest. Merged into
  # each sender's secret_env below, and because the accessor bindings derive from
  # that same table, absent here means absent from IAM too. Adding the GitHub
  # secret is the whole switch: the next deploy passes the slug, the env var and
  # the binding appear together, and no terraform edit is involved.
  mail_secret_env = {
    for app in local.mail_senders : app => (
      contains(local.mail_enabled, app)
      ? { RESEND_API_KEY = google_secret_manager_secret.resend_key[app].secret_id }
      : {}
    )
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

  # The documentation build deadline, written once and read by everything that
  # has to agree with it.
  #
  # Four values must be equal or the build path breaks in a way no gate can
  # see: docs-launcher's request timeout, the docs-build Job's timeout, and the
  # per-task Cloud Tasks dispatchDeadline set by each of the two producers. The
  # launcher holds the Cloud Tasks request open for the whole execution so it
  # can record the outcome from an identity that has the database, so if the
  # dispatch deadline is the smaller of the two, Cloud Tasks abandons and
  # redelivers a build that is still running, forever.
  #
  # Nothing detects that. /api/health answers in milliseconds, so every readiness
  # probe and every deploy gate stays green; the app side specs can only see the
  # task half; and the only symptom is documentation that never appears. So the
  # producers do not carry their own literal, they read
  # DOCS_BUILD_DEADLINE_SECONDS, and that env var and the launcher timeout below
  # are the same local rather than two numbers that happen to match today.
  docs_build_deadline_seconds = var.docs_build_timeout_seconds
  docs_build_timeout          = "${local.docs_build_deadline_seconds}s"

  # The sandbox deadline, derived from the same number but deliberately SMALLER
  # than it. Do not tidy these into one value.
  #
  # docs-launcher holds the Cloud Tasks request open for the whole build and is
  # the only party in the chain with a database credential, so it has to outlive
  # the sandbox in order to record the outcome. Let the sandbox run to the
  # launcher's own deadline and the launcher is killed mid wait having written
  # nothing: the row stays in building forever, no failed_at is written so the
  # retry floor has nothing to measure from, nothing reconsiders it, and no log
  # line says why. That failure is silent rather than noisy, which is exactly
  # the kind that survives a green pipeline.
  #
  # The margin is not padding. It covers the work the launcher does either side
  # of the sandbox wait: clone, checkout, shards install, then downloading the
  # artifact, validating it parses, publishing it and writing status.
  #
  # Ordering, structural rather than coincidental:
  #   docs_sandbox_timeout_seconds  <  docs_build_deadline_seconds
  #                                 == launcher request timeout
  #                                 == docs-build Job timeout
  #                                 == Cloud Tasks dispatchDeadline
  docs_sandbox_timeout_seconds = local.docs_build_deadline_seconds - var.docs_build_launcher_margin_seconds

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
    DOCS_BUILD_QUEUE            = var.docs_build_queue_name
    DOCS_BUILD_QUEUE_LOCATION   = var.docs_build_queue_location
    DOCS_LAUNCHER_URL           = google_cloud_run_v2_service.docs_launcher.uri
    DOCS_TASKS_SERVICE_ACCOUNT  = google_service_account.docs_tasks.email
    DOCS_BUILD_DEADLINE_SECONDS = tostring(local.docs_build_deadline_seconds)
  }

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
      secret_env = merge({
        DATABASE_URL    = var.database_url_secret_ids["crystalgigs"]
        SECRET_KEY_BASE = google_secret_manager_secret.secret_key_base["crystalgigs"].secret_id
        # config/payments.cr calls exit(1) at boot in production without the
        # secret key, so this is a start up dependency and not a lazy one.
        STRIPE_SECRET_KEY      = google_secret_manager_secret.stripe_secret_key.secret_id
        STRIPE_PUBLISHABLE_KEY = google_secret_manager_secret.stripe_publishable_key.secret_id
      }, local.mail_secret_env["crystalgigs"])
    }

    crystalbits = {
      max_instances = 5
      cpu           = "1"
      memory        = "512Mi"
      env = merge(local.common_env, {
        APP_DOMAIN  = var.app_domains["crystalbits"]
        JOB_ADS_URL = var.job_ads_url
      })
      secret_env = merge({
        DATABASE_URL    = var.database_url_secret_ids["crystalbits"]
        SECRET_KEY_BASE = google_secret_manager_secret.secret_key_base["crystalbits"].secret_id
      }, local.mail_secret_env["crystalbits"])
    }
  }

  # Schema migration Jobs.
  #
  # Two variables. That is the whole environment, and the smallness is the point
  # rather than an accident.
  #
  # This deliberately does NOT derive from local.app_config. An earlier version
  # did, because the migration ran `./lucky db.migrate`, and tasks.cr requires
  # src/app, which requires config/**, so a migration loaded the entire serving
  # configuration surface and inherited every one of its boot time demands. That
  # produced a treadmill: PORT, because Cloud Run injects it into services and
  # not into Jobs, then SECRET_KEY_BASE, then the mail key, then
  # PAYMENTS_DISABLED for config/payments.cr, then JOB_ADS_URL for
  # config/job_ads.cr. Each was found by a Job dying rather than by anyone
  # reading, and the supply was not running out.
  #
  # The apps now ship a second binary, ./migrate, built from src/migrate.cr,
  # which requires only shards, app_database, config/database and the
  # migrations. config/server.cr, config/email.cr, config/payments.cr and
  # config/job_ads.cr never load, so none of their variables are needed and none
  # are set. Verified on the real image against a throwaway Postgres with
  # `env -i` and nothing in the environment but these two.
  #
  # Keeping this table independent of the service table is what stops the
  # treadmill restarting: a service that gains a boot time variable tomorrow does
  # not silently turn into a migration that needs one.
  #
  # LUCKY_ENV is required because config/database.cr branches on
  # LuckyEnv.production? to decide whether to read DATABASE_URL at all. Without
  # it the Job assembles a localhost connection from development defaults and
  # migrates nothing, successfully.
  migration_config = {
    for app in local.apps : app => {
      env = {
        LUCKY_ENV = "production"
      }
      secret_env = {
        DATABASE_URL = var.database_url_secret_ids[app]
      }
    }
  }

  # docs-launcher's environment.
  #
  # It is built from the registry codebase, so it inherits that codebase's boot
  # time demands: LUCKY_ENV, APP_DOMAIN, PORT (supplied by Cloud Run through
  # container_port), SECRET_KEY_BASE and JOB_ADS_URL. None of those describe
  # what it does, they are the price of loading config/**.
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
    # Same local that sets this service's request timeout below, so the
    # launcher cannot be told a deadline it does not itself honour.
    DOCS_BUILD_DEADLINE_SECONDS = tostring(local.docs_build_deadline_seconds)
    # And the sandbox deadline, which is that value minus the launcher margin.
    # Only docs-launcher gets this; the two enqueuers never run a build.
    DOCS_SANDBOX_TIMEOUT_SECONDS = tostring(local.docs_sandbox_timeout_seconds)
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
