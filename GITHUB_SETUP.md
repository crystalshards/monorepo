# GitHub Repository Setup Requirements

For continuous deployment to work, you need to configure the following in your GitHub repository:

## 1. Repository Secrets

Go to Settings → Secrets and variables → Actions and add:

### Required Secrets

- `GCP_SA_KEY` - Service account JSON key CI authenticates with
- `GCP_PROJECT_ID` - Target project, passed to Terraform as `TF_VAR_project_id`
- `CRYSTALSHARDS_SENDGRID_KEY`
- `CRYSTALDOCS_SENDGRID_KEY`
- `CRYSTALGIGS_SENDGRID_KEY`
- `CRYSTALBITS_SENDGRID_KEY`
- `DOCS_LAUNCHER_SENDGRID_KEY`
- `CRYSTALGIGS_STRIPE_SECRET_KEY`
- `CRYSTALGIGS_STRIPE_PUBLISHABLE_KEY`

Those nine are the complete set. The pipeline reads no other repository secret.
[`.github/SETUP.md`](.github/SETUP.md) explains what each one is for and how to mint
the Google Cloud key.

## 2. Service Account Permissions

The CI identity deploys the services and runs Terraform, so it needs permission over
everything Terraform manages, not only Cloud Run and Artifact Registry:

- `roles/run.admin`
- `roles/artifactregistry.writer`
- `roles/cloudsql.client`
- `roles/compute.loadBalancerAdmin`
- `roles/dns.admin`
- `roles/secretmanager.admin`
- `roles/iam.serviceAccountUser`
- `roles/storage.admin`
- `roles/serviceusage.serviceUsageAdmin`

[`.github/SETUP.md`](.github/SETUP.md) holds the commands that create this
identity, bind the roles, and configure Artifact Registry. Follow it there rather
than duplicating the setup here.

## 3. Branch Protection Rules

Configure for `main` branch:

- ✅ Require pull request reviews before merging
- ✅ Require status checks to pass before merging
  - `test-crystalshards`
  - `test-crystaldocs`
  - `test-crystalgigs`
  - `build-images`
- ✅ Require branches to be up to date before merging
- ✅ Include administrators

## 4. GitHub Environments

Create environments for deployment stages:

### `staging`

- No required reviewers
- Deployment branches: `main`, `staging/*`
- Secrets: Can inherit from repository

### `production`

- Required reviewers: 1
- Deployment branches: `main`
- Wait timer: 5 minutes
- Secrets: Production-specific overrides

## 5. Webhook Configuration

For CrystalGigs Stripe integration:

1. Add webhook endpoint: `https://crystalgigs.com/webhooks/stripe`
2. Events to listen for:
   - `checkout.session.completed`
   - `invoice.payment_succeeded`
   - `customer.subscription.deleted`

## 6. Actions Permissions

Settings → Actions → General:

- Actions permissions: Allow all actions and reusable workflows
- Workflow permissions: Read and write permissions
- ✅ Allow GitHub Actions to create and approve pull requests

## 7. Container Images

CI pushes to Artifact Registry:

- Repository `docker-images` in `us-central1`
- Image path: `us-central1-docker.pkg.dev/<project>/docker-images/<image>:<sha>`
- Tag: the full 40 character commit SHA
- Five images: `crystalshards`, `crystaldocs`, `crystalgigs`, `crystalbits`, `docs-build`

No `latest` tag is pushed or referenced. That is deliberate rather than an omission:
it means nothing can resolve to a tag the pipeline did not produce.

## 8. Deployment Triggers

Deployments happen on:

- Push to `main` → Deploy to staging
- GitHub release → Deploy to production
- Manual workflow dispatch → Deploy to any environment

## 9. Cost Alerts

Set up billing alerts in GCP:

- Alert at $50/month
- Alert at $100/month
- Hard cap at $150/month (optional)

## 10. Monitoring Integration

GitHub Actions will send metrics to:

- Deployment success/failure → Slack
- Application errors → Sentry
- Performance metrics → Cloud Monitoring, published by Cloud Run
