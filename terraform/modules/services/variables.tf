variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "Region every service and Job runs in"
  type        = string
}

variable "image_repository" {
  description = "Artifact Registry path images are tagged against, without a trailing slash, e.g. us-central1-docker.pkg.dev/<project>/docker-images"
  type        = string
}

variable "image_tag" {
  description = <<-DESC
    Image tag every service and Job is created at. Always a commit SHA, never
    "latest": CI pushes only SHA tags, and a floating tag makes the plan unable
    to answer what is actually serving.

    Terraform sets this at create time and then stops fighting for it. Every
    service and Job carries lifecycle.ignore_changes on the image so CI can roll
    subsequent revisions with `gcloud run services update`.
  DESC
  type        = string
}

variable "docs_launcher_image_name" {
  description = <<-DESC
    Image name within the repository for the docs-launcher service.

    It is "crystalshards", not "docs-launcher". There is no apps/docs-launcher
    and CI builds no such image: the launcher is the registry image deployed a
    second time under a second service name, because the trusted half of a
    documentation build already lives in that codebase. Defaulting this to
    "docs-launcher" would fail the first apply on an image that does not exist.
  DESC
  type        = string
  default     = "crystalshards"
}

variable "docs_build_image_name" {
  description = "Image name within the repository for the docs-build Job. This is the image that runs untrusted third party shard code"
  type        = string
  default     = "docs-build"
}

variable "cloud_sql_connection_name" {
  description = "Instance connection name, mounted as the /cloudsql/<connection_name> socket volume"
  type        = string
}

variable "database_url_secret_ids" {
  description = "Map of app slug to the Secret Manager secret_id holding that database's connection string"
  type        = map(string)
}

variable "docs_bucket_name" {
  description = "Built documentation bucket"
  type        = string
}

variable "packages_bucket_name" {
  description = "Package artifact bucket"
  type        = string
}

variable "docs_build_queue_name" {
  description = "Short name of the Cloud Tasks queue documentation builds are enqueued on"
  type        = string
}

variable "docs_build_queue_location" {
  description = "Location of the Cloud Tasks queue"
  type        = string
}

variable "docs_build_concurrency" {
  description = <<-DESC
    The global documentation build concurrency cap, taken from the queue module
    rather than restated. docs-launcher's max_instances is pinned to it, so the
    dispatcher can never be asked to hold more builds open than the queue is
    willing to have in flight, and the Job's own parallelism is 1.
  DESC
  type        = number
}

variable "docs_build_timeout_seconds" {
  description = <<-DESC
    Ceiling on a single documentation build. docs-launcher holds the Cloud Tasks
    request open for the duration of the execution so it can record the outcome
    from an identity that has the database, which means the launcher's request
    timeout, the Job's timeout and the queue's dispatch deadline all have to sit
    at or above this. The app side default (DOCS_SANDBOX_TIMEOUT_SECONDS) is 900,
    so this leaves headroom rather than racing it.
  DESC
  type        = number
  default     = 1800
}

variable "job_ads_url" {
  description = <<-DESC
    Where the job ad strip reads promotable jobs from. CrystalShards, CrystalDocs
    and CrystalBits all refuse to boot in production without it, by design.

    No default, because any default would hardcode the CrystalGigs hostname a
    third time. The caller builds it from app_domains["crystalgigs"], so the
    strip cannot end up pointed at a host the edge does not serve.
  DESC
  type        = string
}

variable "app_domains" {
  description = <<-DESC
    Map of app slug to the public origin it serves on. Lucky calls
    ENV.fetch("APP_DOMAIN") at boot in production and raises without it.

    Required, with no default, on purpose. These same four hostnames drive the
    managed certificates, the load balancer host rules and the DNS records, and
    a default here would be a second copy of them that nothing compares against
    the first. The failure that prevents is the quiet one: terraform validates,
    the plan is clean, the services boot, and the only symptom is an app
    generating absolute URLs and callbacks for a hostname the load balancer does
    not serve. The single source is local.sites in terraform/locals.sites.tf.
  DESC
  type        = map(string)
}

variable "docs_launcher_app_domain" {
  description = <<-DESC
    APP_DOMAIN for docs-launcher. It serves no public origin of its own and the
    value only feeds Lucky's route helper, so the caller passes the registry
    origin it belongs to. No default, for the same reason as app_domains: a
    hostname written here is a copy nothing reconciles.
  DESC
  type        = string
}

variable "request_concurrency" {
  description = "Concurrent requests per instance. Held below Cloud Run's default of 80 because each instance backs them with a connection pool of five"
  type        = number
  default     = 40
}

variable "request_timeout_seconds" {
  description = "Request timeout for the four public services. A page that has not answered in a minute is not going to"
  type        = number
  default     = 60
}

variable "health_path" {
  description = "Startup probe path. The apps mount health at /api/health, not /health, and a probe on the wrong path burns its whole failure budget on Lucky 404s and then fails the deploy looking like a broken app"
  type        = string
  default     = "/api/health"
}

variable "container_port" {
  description = "Port the container listens on. Cloud Run derives the injected PORT from this and config/server.cr binds to it"
  type        = number
  default     = 8080
}

variable "crystalshards_sendgrid_key" {
  description = "SendGrid API key for CrystalShards. config/email.cr calls exit(1) at boot in production without it. The literal string 'unused' runs the app with outbound email off"
  type        = string
  sensitive   = true
}

variable "crystaldocs_sendgrid_key" {
  description = "SendGrid API key for CrystalDocs. See crystalshards_sendgrid_key"
  type        = string
  sensitive   = true
}

variable "crystalgigs_sendgrid_key" {
  description = "SendGrid API key for CrystalGigs. See crystalshards_sendgrid_key"
  type        = string
  sensitive   = true
}

variable "crystalbits_sendgrid_key" {
  description = "SendGrid API key for CrystalBits. See crystalshards_sendgrid_key"
  type        = string
  sensitive   = true
}

variable "docs_launcher_sendgrid_key" {
  description = "SendGrid API key for docs-launcher. It sends no mail, but it is built from the registry codebase and config/email.cr calls exit(1) at boot in production without the variable. 'unused' is the documented value for no outbound email"
  type        = string
  sensitive   = true
}

variable "crystalgigs_stripe_secret_key" {
  description = "Stripe secret key for CrystalGigs payment processing"
  type        = string
  sensitive   = true
}

variable "crystalgigs_stripe_publishable_key" {
  description = "Stripe publishable key for CrystalGigs. Publishable rather than secret, but it is held in Secret Manager alongside its pair so there is one rotation path for Stripe rather than two"
  type        = string
  sensitive   = true
}
