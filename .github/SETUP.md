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

Those two authenticate CI to Google Cloud. The deploy workflow reads nine more
repository secrets, the third party application and discovery credentials, and
adds a Secret Manager version from each. They are listed below under Populate the
Application Secrets and Turn On Shard Discovery, together with the container id
each one fills.

Terraform creates those containers but never a version for any of them, so no
third party credential is a Terraform variable and none reaches Terraform state.

#### Roles for the deploy service account

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
    "roles/serviceusage.serviceUsageAdmin",
    "roles/cloudscheduler.admin",
    "roles/iam.roleAdmin"
  ]
}
```

The last two arrived with the discovery schedule and are both deploy time
authority, not anything a running service holds.
`roles/cloudscheduler.admin` manages the one Cloud Scheduler job in the stack.
`roles/iam.roleAdmin` is project-wide authority to create and edit custom IAM
roles, and it exists to buy exact least privilege for that schedule: its caller
identity holds a custom role of exactly `run.jobs.run`, because no predefined role
is that small.
[`GITHUB_SETUP.md`](../GITHUB_SETUP.md) records the alternative if you would
rather not grant it.

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

# Required by the shard discovery schedule, the only timer in the stack
gcloud services enable cloudscheduler.googleapis.com
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
    roles/serviceusage.serviceUsageAdmin \
    roles/cloudscheduler.admin \
    roles/iam.roleAdmin; do
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

`terraform/variables.tf` declares exactly five: `project_id`, `region`,
`image_tag`, `mail_enabled_apps` and `discovery_enabled_hosts`. `project_id` and
`region` come from `terraform/terraform.tfvars`. `image_tag` is the commit SHA,
passed on the command line with `-var`. The last two are lists of names the deploy
workflow computes and passes the same way.

Do not add a second source for a variable that already has one. Terraform
auto-loads `terraform.tfvars`, and an auto-loaded values file outranks `TF_VAR_`,
so exporting `TF_VAR_project_id` alongside the tracked file changes nothing while
the run still reports success. That precedence is what let a tracked values file
pinning credentials to a placeholder silently override what CI passed.

No third-party credential is a Terraform variable. The Resend keys, the Stripe
keys and the discovery host tokens all reach their consumers through Secret
Manager instead, so nothing sensitive is written into Terraform state.
`mail_enabled_apps` and `discovery_enabled_hosts` carry names only: which
capability CI found a value for, never the value.

## Initial Infrastructure Deployment

Infrastructure is applied by CI, never from a workstation. CI holds the deployment
credential and the GCS state backend, and applies run there by policy.

After CI applies the change, verify what is running:

```bash
gcloud run services list --region us-central1
gcloud run jobs list --region us-central1
gcloud scheduler jobs list --location us-central1
```

The last of those should list exactly one job, `discover-shards`, on the cadence
in `terraform/modules/scheduler/variables.tf`. It is the only timer in the stack.

## Populate the Application Secrets

Terraform creates nine empty Secret Manager containers, so there is no
`gcloud secrets create` step. Four hold application credentials and five hold
discovery host credentials; the discovery five are in the next section.

The deploy workflow populates them. Its `Populate the application secrets` step
reads the matching GitHub repository secrets and adds a Secret Manager version
from each, so an operator supplies each value once under Settings, then Secrets
and variables, then Actions, and never runs `gcloud` by hand.

| GitHub secret | Secret Manager container | What it unblocks | Absent |
| --- | --- | --- | --- |
| `CRYSTALGIGS_STRIPE_SECRET_KEY` | `crystalgigs-stripe-secret-key` | CrystalGigs payments, server side | Stops the deploy |
| `CRYSTALGIGS_STRIPE_PUBLISHABLE_KEY` | `crystalgigs-stripe-publishable-key` | CrystalGigs payments, browser side | Stops the deploy |
| `CRYSTALGIGS_RESEND_KEY` | `crystalgigs-resend-key` | CrystalGigs mail, which delivers job applications | Mail off on that service, deploy continues |
| `CRYSTALBITS_RESEND_KEY` | `crystalbits-resend-key` | CrystalBits mail, which sends the newsletter | Mail off on that service, deploy continues |

`crystalshards`, `crystaldocs` and `docs-launcher` are deliberately absent and
must stay absent: a registry and a docs site should not refuse to serve a page
because a mail credential is missing, and `docs-launcher` runs the `crystalshards`
image so it inherits that.

Only the two Stripe keys are mandatory. The step fails closed on those, because
`config/payments.cr` exits at boot without them, so the alternative is a revision
that cannot start. A missing mail key is a supported state: the service deploys
and serves, and raises naming `RESEND_API_KEY` on an actual send attempt rather
than reporting a delivery that did not happen. Every skip is printed.

## Turn On Shard Discovery

This is how the registry finds shards on its own. Without it the only paths to an
indexed shard are `POST /api/shards`, `POST /api/shards/upload` and a GitHub
webhook push, which means somebody has to bring every shard by hand.

A Cloud Scheduler job runs the `discover-shards` Cloud Run Job on a cadence. Each
run walks a bounded slice of each configured host's search API and stops; the
crawler saves a per host cursor after every page, so the next run continues rather
than starting over. Every host needs an API credential, and each is independent:

| GitHub secret | Secret Manager container | Crawler variable | Host it turns on |
| --- | --- | --- | --- |
| `DISCOVERY_GITHUB_TOKEN` | `github-token` | `GITHUB_TOKEN` | `github.com` |
| `GITLAB_TOKEN` | `gitlab-token` | `GITLAB_TOKEN` | `gitlab.com` |
| `CODEBERG_TOKEN` | `codeberg-token` | `CODEBERG_TOKEN` | `codeberg.org` |
| `BITBUCKET_USERNAME` | `bitbucket-username` | `BITBUCKET_USERNAME` | `bitbucket.org`, with the row below |
| `BITBUCKET_APP_PASSWORD` | `bitbucket-app-password` | `BITBUCKET_APP_PASSWORD` | `bitbucket.org`, with the row above |

**Set none of these and the registry discovers nothing and stays empty.** That is
the state a fresh deploy is in. The sweep still runs on schedule and still
succeeds: it reports each host as skipped and names the variable that would enable
it, so a run that indexed zero shards reads as nobody having given it a token
rather than as an empty ecosystem. Nothing fails, and nothing pretends to have
looked.

Each token needs public read scope and nothing more. The crawler only enumerates
public repositories and reads `shard.yml` files.

`bitbucket.org` needs both of its secrets before it turns on. Its API takes an app
password over HTTP Basic, and Basic carries the account the password belongs to, so
the password alone authenticates nothing. One half populated leaves the host off
and says which half is missing.

### Why `DISCOVERY_GITHUB_TOKEN` and not `GITHUB_TOKEN`

Because GitHub will not allow the obvious name, and the way it refuses is silent.
Secret names "must not start with the `GITHUB_` prefix"
([docs](https://docs.github.com/en/actions/reference/security/secrets)), so the
repository secret cannot be created, and `${{ secrets.GITHUB_TOKEN }}` in a
workflow always resolves to the installation token GitHub mints for that run
instead. That token is present, non empty, scoped to this repository and expires
in an hour, so reading it would pass every check the populate step makes and then
produce a sweep that authenticates successfully and finds nothing on github.com.

Do not rename this to match the other four. The Secret Manager container is still
`github-token` and the variable the crawler reads is still `GITHUB_TOKEN`, matching
`Discovery::Credentials::TOKEN_ENV`; the alias exists only on the CI input side.

### Adding a version by hand

To add a version outside the pipeline, for a rotation or an emergency:

```bash
gcloud secrets versions add <secret-id> --data-file=- --project=crystalshards-org
```

For the mail and Stripe containers that is enough. For a discovery container it is
not, and this is the one asymmetry worth knowing: Terraform decides which token
environment variables to attach from the list CI publishes, and CI only publishes
a host whose repository secret it read. Terraform cannot check a container for a
version itself, because reading one would write the token into Terraform state. So
a hand added discovery version rotates a host that is already on; it does not turn
a host on. The repository secret is what does that.

### What is running

A Cloud Run revision or execution that references a secret with zero versions
fails to start. It does not start degraded, and it does not start with an empty
string. That is why every optional credential is attached conditionally.

| Service or Job | On a clean apply with no optional secret set |
| --- | --- |
| `crystalshards` | Serves. Holds no third party secret. |
| `crystaldocs` | Serves. Holds no third party secret. |
| `docs-launcher` | Serves. Holds no third party secret. |
| `crystalbits` | Serves. Mail raises naming `RESEND_API_KEY` on a send attempt. |
| `crystalgigs` | Will not start until both Stripe secrets have a version. Mail behaves as CrystalBits does. |
| `discover-shards` | Runs on schedule, reports all four hosts skipped, exits successfully, indexes nothing. |

The four `*-migrate` Jobs are unaffected, holding only the `DATABASE_URL`
Terraform generates, and `docs-build` is unaffected because it holds no secret
at all.

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