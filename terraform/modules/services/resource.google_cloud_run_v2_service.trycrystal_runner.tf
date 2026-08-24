# trycrystal-runner. Executes lesson submissions as `crystal run` and answers
# with stdout, stderr and the final expression's value.
#
# Ingress is ALL, which reads like a mistake and is not, for the same reason
# docs-launcher's is: this stack has no VPC connector or Serverless VPC Access,
# and a Cloud Run service's outbound requests leave through the public path, so
# they do not count as internal traffic at the target. An internal ingress
# setting here would make the runner unreachable from the trycrystal app, which
# is its only legitimate caller. What makes this service private is IAM: the
# single binding in trycrystal_runner_invoker grants run.invoker to the
# trycrystal app's identity alone, so an unauthenticated or third party request
# is a 403 before any handler runs. It is not behind the load balancer and has
# no hostname of its own.
#
# min_instances is 0, and that is a reversal of what this comment used to say.
# The runner was designed as a warm pool (DESIGN.md section 2 and 4) because a
# cold started instance has to boot the toolchain before it can answer, and the
# tutorial is built around sub-second answers. The design was right about the
# mechanism and wrong about the traffic: at trycrystal_runner_cpu and
# trycrystal_runner_memory with cpu_idle false, one pinned instance is billed
# around the clock and was measured at $115.63 a month against 10 lifetime
# requests. Holding a warm pool for a fleet nobody is submitting to is not a
# latency budget, it is a standing charge, so the cold start is back on the
# first submission of every quiet period and that is the correct trade at this
# volume. var.trycrystal_runner_min_instances records what evidence would
# justify pinning it warm again; the short version is sustained submissions,
# not a preference about how the first one feels.
#
# Concurrency is 1 on purpose, not a placeholder. The runner serializes
# executions per instance by construction, and the confinement analysis in
# apps/trycrystal/sandbox/VERIFICATION.md found that concurrent submissions on
# one instance share a uid: kill(2) between siblings is not denied by the
# sandbox's filters, so container_concurrency above 1 would let a hostile
# submission DoS its own instance's neighbours. Throughput comes from
# max_instances, not from concurrency.
#
# cpu_idle is false, and with min_instances at 0 that no longer means "keep a
# deliberately warm instance warm". It now means an instance that exists is an
# instance a visitor is working in: a lesson is a run, an edit and another run,
# and throttling the CPU between those would put a warmup in front of every
# submission after the first instead of only the first. The cost of cpu_idle
# false is now bounded by how long anyone is actually using the tutorial, which
# is the bound that was missing while an instance was pinned up permanently.
#
# There is no cloudsql volume, no secret, no env var beyond TRYC_SANDBOX (see
# local.trycrystal_runner_env), no dependency on any secret grant, and the
# template's service account holds no IAM bindings anywhere. The revision
# fails to start if the image is wrong or the runner refuses its own
# confinement; both of those are the desired direction to fail in.
#
# The startup probe hits the runner's own /health, which answers 200 only when
# the runner has verified its confinement (uid, filesystem, egress filter) and
# refuses otherwise, so a revision that cannot enforce the sandbox is never
# promoted, under a green apply, onto traffic.
resource "google_cloud_run_v2_service" "trycrystal_runner" {
  project = var.project_id
  # Shared with everything that names this service.
  name     = local.trycrystal_runner_service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # The audience the trycrystal app mints its ID token for. Declared here so
  # Cloud Run accepts a token bearing it, and read by the app from
  # local.trycrystal_runner_audience, the one local both sides share. A literal
  # rather than this service's own URL because a resource cannot consume its
  # own output; see local.trycrystal_runner_audience.
  custom_audiences = [local.trycrystal_runner_audience]

  template {
    service_account                  = google_service_account.trycrystal_runner.email
    timeout                          = "${var.trycrystal_runner_timeout_seconds}s"
    max_instance_request_concurrency = var.trycrystal_runner_concurrency

    scaling {
      min_instance_count = var.trycrystal_runner_min_instances
      max_instance_count = var.trycrystal_runner_max_instances
    }

    containers {
      image = local.trycrystal_runner_image

      ports {
        name           = "http1"
        container_port = var.trycrystal_runner_port
      }

      resources {
        limits = {
          cpu    = var.trycrystal_runner_cpu
          memory = var.trycrystal_runner_memory
        }
        cpu_idle          = false
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = local.trycrystal_runner_env
        content {
          name  = env.key
          value = env.value
        }
      }

      startup_probe {
        initial_delay_seconds = 5
        period_seconds        = 5
        timeout_seconds       = 3
        failure_threshold     = 12

        http_get {
          path = var.trycrystal_runner_health_path
          port = var.trycrystal_runner_port
        }
      }
    }
  }

  labels = {
    app         = "trycrystal"
    component   = "runner"
    environment = "production"
    managed_by  = "terraform"
  }

  lifecycle {
    ignore_changes = [
      # CI owns the tag after creation. See var.image_tag. An unregistered
      # build would otherwise leave this service on its creation image forever
      # behind a green apply; see apps/trycrystal/REGISTRATION.md.
      template[0].containers[0].image,
      # gcloud stamps these on every `run services update` and terraform would
      # otherwise propose reverting them on the next plan, forever.
      client,
      client_version,
    ]
  }
}
