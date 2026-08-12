# docs-build. Runs `crystal docs` over third party shard source.
#
# Read the comment on google_service_account.docs_build before changing
# anything here. The short version: every execution of this Job runs code
# written by a stranger, because Crystal macros execute at compile time, and
# the identity attached to it holds no IAM bindings anywhere in this project.
#
# That is why this resource has no secrets, no database, no Cloud SQL volume
# and no bucket names in its environment. It receives a signed GET URL for its
# input and a signed PUT URL for its output as execution overrides from
# docs-launcher, and those two URLs are the entire surface it can reach. It
# does not know what the buckets are called and does not need to.
#
# max_retries is 0 rather than the Cloud Run default of 3. The Cloud Tasks
# queue already owns the retry policy, and leaving both on multiplies them: a
# task with three attempts against a Job with three retries is nine builds of
# something that was never going to compile.
#
# Gen2 execution environment because a Crystal compile wants a full Linux
# filesystem, and the resources are the largest thing in this module because
# compilation is the only genuinely heavy workload here.
#
# THERE IS DELIBERATELY NO vpc_access BLOCK, AND NO EGRESS SETTING.
#
# The compile phase has no network, but that is not arranged here and could
# not be. A Cloud Run egress setting is a property of the whole task, and this
# task genuinely needs egress: its source arrives over a signed GET and its
# artifact leaves over a signed PUT. Routing it through a VPC would break the
# phase that has to work and would not constrain the phase that must not.
#
# It would also miss the target. 169.254.169.254 mints access tokens for this
# Job's service account, and link-local traffic is answered inside the sandbox
# without ever touching a VPC, so no egress setting covers it. A control that
# stops the public internet and leaves the metadata server reachable has shut
# the cheap half of the hole.
#
# The confinement is inside the image instead: apps/docs-build runs the
# compile behind a seccomp filter it installs on itself, which is inherited,
# survives execve and cannot be removed, and it drops to an unprivileged uid
# so the compile cannot read the signed urls out of the supervisor. See
# apps/docs-build/sandbox/no-egress.c. If a future edit adds a VPC connector
# here, it is defence in depth and not the boundary; do not remove anything
# from the image on the strength of it.
resource "google_cloud_run_v2_job" "docs_build" {
  project  = var.project_id
  name     = "docs-build"
  location = var.region

  template {
    parallelism = 1
    task_count  = 1

    template {
      service_account       = google_service_account.docs_build.email
      timeout               = local.docs_build_timeout
      max_retries           = 0
      execution_environment = "EXECUTION_ENVIRONMENT_GEN2"

      containers {
        image = local.docs_build_image

        resources {
          limits = {
            cpu    = "2"
            memory = "4Gi"
          }
        }
      }
    }
  }

  labels = {
    app         = "docs-build"
    environment = "production"
    managed_by  = "terraform"
  }

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}
