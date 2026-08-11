# GitHub Repository Setup Requirements

For continuous deployment to work, you need to configure the following in your GitHub repository:

## 1. Repository Secrets

Go to Settings → Secrets and variables → Actions and add:

### Required Secrets

- `STRIPE_SECRET_KEY` - Stripe secret key for CrystalGigs
- The GCP deployment credential the deploy workflow expects, which authenticates
  CI to Google Cloud

## 2. Service Account Permissions

The CI identity needs these roles:

- `roles/artifactregistry.writer` - Push container images to Artifact Registry
- `roles/run.admin` - Deploy Cloud Run services and jobs
- `roles/iam.serviceAccountUser` - Act as the runtime service accounts

Terraform runs in CI under the same identity, so it also needs permission over
every resource declared under `terraform/`.

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
- Image path: `us-central1-docker.pkg.dev/crystalshards-org/docker-images/<app>:<sha>`

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
