# GitHub Actions Setup Guide

This guide explains how to configure the required secrets and environment variables for the CI/CD pipeline.

## Required GitHub Secrets

### Google Cloud Platform Integration

#### `GCP_SA_KEY`

The service account JSON key CI authenticates with. `google-github-actions/auth`
reads it as `credentials_json`, so the secret holds the contents of the key file.

#### `GCP_PROJECT_ID`

The Google Cloud project the Cloud Run services are deployed into.

**Example**: `crystalshards-org`

Those two are what the Terraform deploy path requires. The deploy workflow may
consume other secrets for steps outside Terraform; `.github/workflows/` is the
authority on that.

The SendGrid and Stripe keys are not repository secrets. Terraform never sees them.
They live in Secret Manager and an operator adds each version by hand, which is
covered below under Populate the Application Secrets.

#### Roles for the deploy service account

The same identity deploys the services and runs Terraform, so it needs permission
over everything Terraform manages, not only Cloud Run and Artifact Registry:

```json
{
  "roles": [
    "roles/run.admin",
    "roles/artifactregistry.writer",
    "roles/cloudsql.client",
    "roles/compute.loadBalancerAdmin",
    "roles/dns.admin",
    "roles/secretmanager.admin",
    "roles/iam.serviceAccountUser",
    "roles/storage.admin",
    "roles/serviceusage.serviceUsageAdmin"
  ]
}
```

## GitHub Environments

The pipeline uses GitHub Environments for deployment protection and secrets
management. [`GITHUB_SETUP.md`](../GITHUB_SETUP.md) defines the environments and
their protection rules. Configure them there so the two documents cannot drift
apart.

## Google Cloud Project Setup

### 1. Enable Required APIs

```bash
gcloud services enable run.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable cloudtasks.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable dns.googleapis.com
gcloud services enable monitoring.googleapis.com

# Required by the global external Application Load Balancer and its serverless NEGs
gcloud services enable compute.googleapis.com
```

### 2. Create Service Account

```bash
# Create service account
gcloud iam service-accounts create crystalshards-ci \
    --display-name="CrystalShards CI/CD Service Account" \
    --description="Service account for GitHub Actions CI/CD"

# Grant required roles
PROJECT_ID="crystalshards-org"
SA_EMAIL="crystalshards-ci@${PROJECT_ID}.iam.gserviceaccount.com"

for ROLE in \
    roles/run.admin \
    roles/artifactregistry.writer \
    roles/cloudsql.client \
    roles/compute.loadBalancerAdmin \
    roles/dns.admin \
    roles/secretmanager.admin \
    roles/iam.serviceAccountUser \
    roles/storage.admin \
    roles/serviceusage.serviceUsageAdmin; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
      --member="serviceAccount:$SA_EMAIL" \
      --role="$ROLE"
done

# Create the JSON key that the GCP_SA_KEY secret holds
gcloud iam service-accounts keys create crystalshards-ci-key.json \
    --iam-account=$SA_EMAIL
```

`google-github-actions/auth` accepts the raw JSON, so base64 encoding is optional.
Minify the key to a single line before pasting it into `GCP_SA_KEY`. GitHub masks a
secret line by line, and an unminified key makes it sanitize ordinary braces and
brackets in log output:

```bash
tr -d '\n' < crystalshards-ci-key.json
```

Delete the local key file once the secret is set.

### 3. Configure Artifact Registry

Images live in the `docker-images` repository in `us-central1`. The full image path
is `us-central1-docker.pkg.dev/<project>/docker-images/<image>:<sha>`, where the tag
is the full 40 character commit SHA. No `latest` tag is pushed or referenced, so
nothing can resolve to a tag the pipeline did not produce.

```bash
# Create the repository
gcloud artifacts repositories create docker-images \
    --repository-format=docker \
    --location=us-central1 \
    --description="Container images for the CrystalShards services"

# Authenticate Docker against the registry host
gcloud auth configure-docker us-central1-docker.pkg.dev
```

The `roles/artifactregistry.writer` binding above already covers pushes, so the CI
identity needs no further grant on the repository.

## Terraform Variables

`terraform/variables.tf` declares exactly three: `project_id`, `region` and
`image_tag`. `project_id` and `region` come from `terraform/terraform.tfvars`.
`image_tag` is the commit SHA, passed on the command line with `-var`.

Do not add a second source for a variable that already has one. Terraform
auto-loads `terraform.tfvars`, and an auto-loaded values file outranks `TF_VAR_`,
so exporting `TF_VAR_project_id` alongside the tracked file changes nothing while
the run still reports success. That precedence is how a values file pinning
credentials to `"unused"` once overrode what CI passed.

No third-party credential is a Terraform variable. The SendGrid and Stripe keys
reach the services through Secret Manager instead, so nothing sensitive is written
into Terraform state.

## Initial Infrastructure Deployment

Infrastructure is applied by CI, never from a workstation. CI holds the deployment
credential and the GCS state backend, and applies run there by policy.

After CI applies the change, verify what is running:

```bash
gcloud run services list --region us-central1
gcloud run jobs list --region us-central1
```

## Populate the Application Secrets

Terraform creates these seven as empty Secret Manager containers, so there is no
`gcloud secrets create` step. Each one needs a version added by hand:

- `crystalshards-sendgrid-key`
- `crystaldocs-sendgrid-key`
- `crystalgigs-sendgrid-key`
- `crystalbits-sendgrid-key`
- `docs-launcher-sendgrid-key`
- `crystalgigs-stripe-secret-key`
- `crystalgigs-stripe-publishable-key`

```bash
gcloud secrets versions add <secret-id> --data-file=- --project=crystalshards-org
```

On a clean apply no site serves until all seven have a version. A Cloud Run
revision that references a secret with zero versions fails to start. It does not
start degraded, and it does not start with an empty string.

All five services are blocked, not only the one taking payments. Every Lucky
service reads `SEND_GRID_KEY`, and `config/email.cr` calls `exit(1)` at boot in
production without it, so `crystalshards`, `crystaldocs`, `crystalbits` and
`docs-launcher` each wait on their own SendGrid secret, and `crystalgigs` waits on
all three of its SendGrid, Stripe secret and Stripe publishable keys. The four
migrate Jobs are unaffected, holding only the `DATABASE_URL` Terraform generates,
and `docs-build` is unaffected because it holds no secret at all.

To run a service without outbound mail, set that service's SendGrid secret to the
literal string `unused`, the value `config/email.cr` names in its own error
message. That is an operator decision recorded in Secret Manager, which is not the
same thing as a fake value committed to a tracked file. Stripe has no equivalent:
CrystalGigs needs real Stripe keys or it does not serve.

## Security Considerations

### Secrets Management
- Never commit secrets to the repository
- Use GitHub's encrypted secrets for sensitive data
- Rotate the deploy credential on a regular schedule
- Use least-privilege access for service accounts

### Access Control
- Enable branch protection on `main` branch
- Require pull request reviews for production deployments
- Use environment protection rules for sensitive deployments
- Enable security advisories and Dependabot

### Image Security
- Enable Trivy security scanning in CI pipeline
- Use minimal base images (Alpine Linux)
- Regularly update base images and dependencies
- Scan for vulnerabilities before deployment

## Monitoring and Alerting

### CI/CD Monitoring
- Set up Slack/Discord webhooks for deployment notifications
- Monitor workflow execution times and failure rates
- Set up alerts for failed deployments or security vulnerabilities

### Application Monitoring
- Request logs and container logs in Cloud Logging
- Request count, latency and instance count in Cloud Monitoring, published by Cloud Run
- Cloud SQL instance metrics in Cloud Monitoring

## Troubleshooting

### Common Issues

#### Authentication Errors
```bash
# Verify the CI identity holds the expected roles
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:$SA_EMAIL" \
    --format="table(bindings.role)"

# Confirm which identity the current session is using
gcloud auth list
```

#### Artifact Registry Access
```bash
# Test registry access
gcloud auth configure-docker us-central1-docker.pkg.dev
gcloud artifacts docker images list \
    us-central1-docker.pkg.dev/$PROJECT_ID/docker-images
```

#### Cloud Run Access
```bash
# Confirm the deploy identity can see the services
gcloud run services list --region us-central1 --project $PROJECT_ID
```

### Debugging Workflows

1. Check workflow logs in GitHub Actions tab
2. Verify secret values are set correctly  
3. Ensure service account has required permissions
4. Test Terraform configuration locally
5. Verify the services are listed by `gcloud run services list --region us-central1`

## Cost Optimization

### Monitoring Costs
- Set up billing alerts for unexpected charges
- Monitor resource usage with Cloud Monitoring
- Review Cloud Run request count and instance time in the billing breakdown
- Watch Cloud SQL and Cloud Storage, the standing costs while Cloud Run idles at zero

### Resource Optimization
- Set appropriate resource limits on containers
- Cloud Run scales to zero when idle, with no extra component to install
- Schedule regular cleanup of old container images
- Monitor storage usage and implement lifecycle policies

## Next Steps

After completing the setup:

1. Test the CI pipeline with a sample commit
2. Verify applications deploy successfully
3. Confirm logs and metrics are arriving in Cloud Logging and Cloud Monitoring
4. Configure alerting rules
5. Document operational procedures

For additional help, check the troubleshooting section or create an issue in the repository.