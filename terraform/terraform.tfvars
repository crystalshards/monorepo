# Terraform variables for the CrystalShards Cloud Run deployment.
#
# NON SECRET VALUES ONLY. This file is tracked in git, and a values file takes
# precedence over TF_VAR_ environment variables, so anything set here silently
# overrides what CI passes. It previously carried four secret variables pinned
# to the literal "unused", which meant the real keys CI supplied as
# TF_VAR_<name> never reached Secret Manager and every app booted with mail and
# payments disabled while the pipeline looked green.
#
# Secrets and image_tag come from CI as TF_VAR_<name> environment variables and
# -var="image_tag=<sha>". See terraform.tfvars.example for the full list.

project_id = "crystalshards-org"
region     = "us-central1"
