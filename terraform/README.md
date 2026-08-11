# CrystalShards Terraform Infrastructure

Terraform configuration for the CrystalShards platform on Google Cloud.

The platform runs on Cloud Run. Managed GCP services provide the database,
object storage, queueing and edge: Cloud SQL, Cloud Storage, Cloud Tasks,
Secret Manager, and one global external Application Load Balancer. Nothing
runs on a container orchestrator, and there are no self hosted operators for
database, cache, storage or ingress.

## Layout

Root configuration wires modules together. Each module lives in
`modules/<name>/` and documents its own inputs and outputs in
`variables.tf` and `outputs.tf`. Module wiring lives in one `module.<name>.tf`
per module at the root, so what is deployed can be read off the file listing.

Resources are one per file, named `resource.<type>.<name>.tf`, matching the
convention already used across the modules.

## Setup

1. Copy the example variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your GCP project details:

   ```hcl
   project_id = "crystalshards-org"
   region     = "us-central1"
   ```

3. Validate locally:

   ```bash
   terraform fmt -check
   terraform init -backend=false
   terraform validate
   ```

## Applying

Applies run in CI against the GCS backend, never from a workstation. Locally,
restrict yourself to `fmt`, `init -backend=false`, `validate` and `plan`.

State lives in the `crystalshards-org-terraform-state` bucket under the
`terraform/state` prefix. CI passes `-backend=false` when it only needs to
validate.
