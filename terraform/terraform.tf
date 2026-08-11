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
      source  = "hashicorp/google"
      version = "~> 4.84"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
