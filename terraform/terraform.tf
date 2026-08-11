terraform {
  required_version = ">= 1.0"

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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
