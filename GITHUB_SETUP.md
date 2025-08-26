# GitHub Repository Setup Requirements

For continuous deployment to work, you need to configure the following in your GitHub repository:

## 1. Repository Secrets

Go to Settings → Secrets and variables → Actions and add:

### Required Secrets

- `GKE_PROJECT` - Your Google Cloud Project ID
- `GKE_CLUSTER_NAME` - Name of your GKE cluster (e.g., `crystalshards-cluster`)
- `GKE_ZONE` - GKE cluster zone (e.g., `us-central1-a`)
- `GKE_SA_KEY` - Service account JSON key with GKE deployment permissions
- `STRIPE_SECRET_KEY` - Stripe secret key for CrystalGigs
- `DOCKERHUB_USERNAME` - Docker Hub username (for pushing images)
- `DOCKERHUB_TOKEN` - Docker Hub access token

## 2. Service Account Permissions

The GKE service account needs these roles:

- `roles/container.developer` - Deploy to GKE

Create with:

```bash
gcloud iam service-accounts create github-actions \
    --description="GitHub Actions CI/CD" \
    --display-name="GitHub Actions"

gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:github-actions@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/container.developer"

gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:github-actions@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.admin"

gcloud iam service-accounts keys create key.json \
    --iam-account=github-actions@PROJECT_ID.iam.gserviceaccount.com
```

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

## 7. Container Registry

The CI/CD will push to:

- GitHub Container Registry: `ghcr.io/crystalshards/*`
- Ensure packages are set to public or configure pull secrets

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
- Performance metrics → Prometheus (in-cluster)
