# docs-build-core. Runs `crystal docs` over Crystal's own standard library,
# publishing it as the `crystal` package so core types resolve to pages on
# this site instead of an external link. See CrystalShards::CoreDocs.
#
# Same Dockerfile as docs_build (apps/docs-build), same entrypoint, same
# seccomp confinement, same unprivileged compile user. The only difference is
# baked into the image at build time: EXTRA_PACKAGES="llvm-dev llvm-static",
# because src/docs_main.cr requires the whole standard library, which pulls in
# src/llvm.cr, whose macros shell out to llvm-config at compile time. Without
# those two packages the build dies on "Could not find location of
# llvm-config" before it ever reaches the confinement this Job shares with
# docs_build.
#
# A second Job rather than a second image built the same way docs_build is,
# and NOT an override of docs_build's own image at run time, for the same
# reason docs_build carries no vpc_access block: what a Cloud Run Job runs is
# baked into its template, and the only correct way to run a different image
# is a different Job. Reusing docs_build here would mean either shipping
# llvm-dev/llvm-static in the image that compiles strangers' shard code, which
# has no business carrying packages that exist for one repository, or racing
# two callers over which image tag is configured, which is not a race this
# stack can win.
#
# Read the comment on google_service_account.docs_build before changing the
# service_account below: this Job reuses that identity rather than minting a
# second one. Reasoning still holds unchanged for THIS Job's source, even
# though it is Crystal's own official repository at a pinned tag rather than a
# stranger's: `crystal docs` still expands macros at compile time, llvm.cr's
# macro among them, so the compile still runs code neither this Job's identity
# nor its confinement should have to trust. The identity earns nothing extra
# by being shared: it holds zero IAM bindings before and after, on either Job.
#
# Resources are larger than docs_build's. A shard is a handful of files; the
# standard library is the whole language, verified in the sandbox that proved
# this recipe to produce a 12MB artifact describing 139 top level types in one
# compile, and linking against LLVM is heavier than the pure-Crystal link a
# shard's macros normally trigger.
#
# max_retries is 0 for the same reason as docs_build: the Cloud Tasks queue
# already owns the retry policy for a build reached through docs-launcher, and
# stacking Cloud Run's own retries on top would multiply attempts at nothing
# that was ever going to compile differently the second time.
#
# timeout matches docs_build's, not a larger number invented for this Job.
# DocsSandbox.timeout_seconds is a single shared budget four values already
# have to agree on (see local.docs_sandbox_timeout_seconds), and giving this
# Job a different one would break that equality for every build, not just
# this one. If the standard library ever needs longer than that budget, the
# fix is raising var.docs_build_timeout_seconds for both Jobs together, not
# forking the number here.
resource "google_cloud_run_v2_job" "docs_build_core" {
  project  = var.project_id
  name     = "docs-build-core"
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
        image = local.docs_build_core_image

        resources {
          limits = {
            cpu    = "4"
            memory = "8Gi"
          }
        }
      }
    }
  }

  labels = {
    app         = "docs-build-core"
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
