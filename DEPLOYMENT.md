# Deployment Guide

## Prerequisites

### GitHub Secrets Configuration

To enable automatic deployment to Google Cloud Platform, configure the following secrets in your GitHub repository:

1. Go to your repository → Settings → Secrets and variables → Actions
2. Add these repository secrets:

#### Required Secrets

- `GCP_PROJECT_ID`: Your Google Cloud Project ID
- `GCP_SA_KEY`: Service Account JSON key with following permissions:
  - Kubernetes Engine Developer
  - Storage Admin
  - Container Registry Service Agent
  - Cloud SQL Client (if using external database)

**OR** 

- `WIF_PROVIDER`: Workload Identity Federation provider (recommended for security)

### Creating Service Account

```bash
# Set your project ID
export PROJECT_ID=your-project-id

# Create service account
gcloud iam service-accounts create crystalshards-ci \
  --description="CI/CD service account for CrystalShards" \
  --display-name="CrystalShards CI"

# Assign necessary roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:crystalshards-ci@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:crystalshards-ci@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Create and download key
gcloud iam service-accounts keys create crystalshards-ci-key.json \
  --iam-account=crystalshards-ci@$PROJECT_ID.iam.gserviceaccount.com
```

### Setting up the Cluster

1. **Create GKE Cluster** (if not exists):
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

2. **Deploy Infrastructure**:
```bash
./scripts/deploy-infrastructure.sh
```

## CI/CD Pipeline

The project uses GitHub Actions for automated:

- **Continuous Integration**: Tests, linting, security scanning
- **Build**: Docker image building and vulnerability scanning  
- **Deploy**: Kubernetes deployment with zero-downtime updates

### Workflows

1. **`ci.yml`**: Runs on all PRs and pushes
   - Crystal dependency installation
   - Unit and integration tests
   - Code formatting checks
   - E2E browser tests

2. **`security.yml`**: Security scanning
   - SARIF security scanning
   - Dependency vulnerability checks
   - Secret detection

3. **`build-and-deploy.yml`**: Build and deployment
   - Docker image building
   - Container vulnerability scanning
   - Kubernetes deployment
   - Smoke tests

### Manual Deployment

To deploy manually:

```bash
# Build and push images
make build-images

# Deploy to staging
gh workflow run "Build and Deploy" -f environment=staging

# Deploy to production  
gh workflow run "Build and Deploy" -f environment=production
```

## Environment Configuration

### Staging
- Namespace: `*-staging`
- Resource limits: Smaller (development workloads)
- Scale to zero after 5 minutes idle

### Production
- Namespace: `crystalshards`, `crystaldocs`, `crystalgigs`
- Resource limits: Production-ready
- High availability with multiple replicas

## Monitoring

Access monitoring dashboards:
- **Grafana**: `http://grafana.crystalshards.org`
- **Prometheus**: `http://prometheus.crystalshards.org`

Key metrics monitored:
- Application response times
- Error rates
- Database performance
- Resource utilization
- Background job processing

## Troubleshooting

### Common Issues

1. **Authentication Failure**
   ```
   google-github-actions/auth failed with: the GitHub Action workflow must specify exactly one of "workload_identity_provider" or "credentials_json"
   ```
   **Solution**: Configure `GCP_SA_KEY` or `WIF_PROVIDER` secret in GitHub repository

2. **Image Push Failure**
   ```
   unauthorized: authentication required
   ```
   **Solution**: Verify service account has `roles/storage.admin` and `roles/container.developer`

3. **Deployment Timeout**
   ```
   timed out waiting for the condition
   ```
   **Solution**: Check pod logs with `kubectl logs -f deployment/app-name -n namespace`

### Debug Commands

```bash
# Check pod status
kubectl get pods -A -l app.kubernetes.io/part-of=crystalshards

# View logs
kubectl logs -f deployment/shards-registry -n crystalshards

# Check resource usage
kubectl top pods -A

# Test service connectivity
kubectl run debug --image=curlimages/curl --rm -i --restart=Never \
  -- curl -f http://shards-registry.crystalshards.svc.cluster.local/health
```

## Cost Optimization

The deployment is configured for cost efficiency:

- **KEDA Autoscaling**: Scale to zero when idle (5 min timeout)
- **Resource Limits**: Right-sized for actual usage
- **Spot Instances**: Worker nodes use preemptible instances
- **In-Cluster Services**: No external cloud service costs

Expected monthly costs:
- **Staging**: ~$50-100 (scales to zero frequently)
- **Production**: ~$200-400 (depends on traffic)