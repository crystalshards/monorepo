# GitHub Actions Setup Guide

This guide explains how to configure the required secrets and environment variables for the CI/CD pipeline.

## Required GitHub Secrets

### Google Cloud Platform Integration

#### `GCP_PROJECT_ID`
Your Google Cloud Project ID where the GKE cluster will be deployed.

**Example**: `crystalshards-prod-12345`

#### `GCP_SA_KEY`
Service Account key (JSON format) for deployment automation.

**Setup Steps**:
1. Create a service account in GCP Console
2. Grant the following roles:
   - `Kubernetes Engine Admin`
   - `Storage Admin` (for container registry)
   - `Compute Admin` (for GKE management)
   - `Service Account User`
3. Create and download a JSON key
4. Base64 encode the JSON: `cat key.json | base64 -w 0`
5. Add the base64 string as the secret value

**Required Permissions**:
```json
{
  "roles": [
    "roles/container.admin",
    "roles/storage.admin", 
    "roles/compute.admin",
    "roles/iam.serviceAccountUser"
  ]
}
```

## GitHub Environments

The pipeline uses GitHub Environments for deployment protection and secrets management.

### Create Environments

1. Go to repository Settings → Environments
2. Create two environments:
   - `staging`
   - `production`

### Environment Protection Rules

#### Staging Environment
- **Required reviewers**: None (auto-deploy)
- **Deployment branches**: Any branch

#### Production Environment  
- **Required reviewers**: Repository admins
- **Deployment branches**: `main` only
- **Wait timer**: 5 minutes

## Google Cloud Project Setup

### 1. Enable Required APIs

```bash
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable monitoring.googleapis.com
```

### 2. Create Service Account

```bash
# Create service account
gcloud iam service-accounts create crystalshards-ci \
    --display-name="CrystalShards CI/CD Service Account" \
    --description="Service account for GitHub Actions CI/CD"

# Grant required roles
PROJECT_ID="your-project-id"
SA_EMAIL="crystalshards-ci@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/container.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/compute.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/iam.serviceAccountUser"

# Create and download key
gcloud iam service-accounts keys create crystalshards-ci-key.json \
    --iam-account=$SA_EMAIL

# Base64 encode for GitHub secret
cat crystalshards-ci-key.json | base64 -w 0 > crystalshards-ci-key.b64
```

### 3. Configure Container Registry

```bash
# Enable Container Registry
gcloud services enable containerregistry.googleapis.com

# Ensure the service account can push to registry
gsutil iam ch serviceAccount:$SA_EMAIL:objectAdmin gs://artifacts.$PROJECT_ID.appspot.com
```

## Terraform Variables Setup

Create `terraform.tfvars` in the terraform directory:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"

# Cluster configuration
cluster_name     = "crystalshards-cluster"
node_count       = 1
machine_type     = "e2-standard-4" 
disk_size_gb     = 50

# Cost optimization
enable_autopilot = true
preemptible      = true
```

## Initial Infrastructure Deployment

Before the CI/CD pipeline can deploy applications, you need to set up the infrastructure:

```bash
# 1. Deploy Terraform infrastructure
cd terraform
terraform init
terraform plan
terraform apply

# 2. Get cluster credentials
gcloud container clusters get-credentials crystalshards-cluster \
    --region us-central1 --project your-project-id

# 3. Deploy infrastructure components  
cd ../
./scripts/deploy-infrastructure.sh

# 4. Verify deployment
kubectl get all -A
```

## Security Considerations

### Secrets Management
- Never commit secrets to the repository
- Use GitHub's encrypted secrets for sensitive data
- Rotate service account keys regularly (every 90 days)
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
- Prometheus metrics collection enabled
- Grafana dashboards for application performance
- KEDA scaling metrics and events
- Database performance monitoring

## Troubleshooting

### Common Issues

#### Authentication Errors
```bash
# Verify service account has correct permissions
gcloud iam service-accounts get-iam-policy $SA_EMAIL

# Test authentication
gcloud auth activate-service-account --key-file=crystalshards-ci-key.json
gcloud auth list
```

#### Container Registry Access
```bash
# Test registry access
docker pull gcr.io/$PROJECT_ID/test
gcloud auth configure-docker
```

#### Kubernetes Access
```bash
# Verify cluster access
gcloud container clusters get-credentials crystalshards-cluster \
    --region us-central1 --project $PROJECT_ID
kubectl cluster-info
```

### Debugging Workflows

1. Check workflow logs in GitHub Actions tab
2. Verify secret values are set correctly  
3. Ensure service account has required permissions
4. Test Terraform configuration locally
5. Verify Kubernetes cluster is accessible

## Cost Optimization

### Monitoring Costs
- Set up billing alerts for unexpected charges
- Monitor resource usage with Cloud Monitoring
- Use preemptible nodes to reduce compute costs
- Enable cluster autoscaling to optimize node usage

### Resource Optimization
- Set appropriate resource limits on containers
- Use KEDA scale-to-zero during idle periods
- Schedule regular cleanup of old container images
- Monitor storage usage and implement lifecycle policies

## Next Steps

After completing the setup:

1. Test the CI pipeline with a sample commit
2. Verify applications deploy successfully
3. Set up monitoring dashboards
4. Configure alerting rules
5. Document operational procedures

For additional help, check the troubleshooting section or create an issue in the repository.