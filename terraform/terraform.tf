terraform {
  # 1.7 is the real floor, not a preference. imports.edge.tf uses for_each
  # inside an import block, added in Terraform 1.7, and the configuration does
  # not parse below it. Plain import blocks are 1.5, so the previous ">= 1.0"
  # was already false before the Cloud Run migration. No local check catches
  # this: CI and every workstation here run a version that satisfies both
  # constraints, so fmt and validate stay green either way. The declaration is
  # the only thing protecting someone on an older binary.
  required_version = ">= 1.7"

  # GCS backend for persistent state
  # CI validation uses -backend=false flag
  backend "gcs" {
    bucket = "crystalshards-org-terraform-state"
    prefix = "terraform/state"
  }

  required_providers {
    google = {
      source = "hashicorp/google"
      # 5.x for google_cloud_run_v2_service.custom_audiences, which arrived in
      # that major and is the only supported way to give docs-launcher an OIDC
      # audience it can verify.
      #
      # The audience has to be known by the enqueuer that mints the token and
      # by the launcher that checks it. Its own URL cannot serve: that is an
      # output of the launcher's resource and terraform will not let a resource
      # consume its own output. Copying the hostname into a variable would put a
      # business fact in configuration with nothing to reconcile it against, and
      # a data source reading the service back cannot plan against an empty
      # project. A declared custom audience is an input both sides can hold.
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
