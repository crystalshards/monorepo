# CrystalShards Infrastructure Deployment Runbook

**Last Updated**: 2025-10-07
**Status**: Ready for deployment - All code complete, awaiting Terraform apply

## Current State

✅ **Complete**:

- All Terraform modules written and validated
- All Kubernetes resources defined (Deployments, Services, Ingresses)
- PostgreSQL clusters (CloudNativePG operator)
- Redis cluster configuration
- MinIO tenant for object storage
- All 4 Lucky applications built and tested
- Docker images building in CI
- E2E tests written

⏳ **Blocker**: Artifact Registry repository must be created before Docker images can be pushed

## Prerequisites

### 1. GCP Project Setup

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable required APIs
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  cloudresourcemanager.googleapis.com

# Verify APIs are enabled
gcloud services list --enabled | grep -E "(container|artifactregistry)"
```

### 2. Service Account for CI/CD

The GitHub Actions workflows need a service account with proper permissions:

```bash
# Create service account
gcloud iam service-accounts create crystalshards-ci \
  --project=$PROJECT_ID \
  --description="CI/CD service account for CrystalShards" \
  --display-name="CrystalShards CI"

# Grant required roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:crystalshards-ci@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:crystalshards-ci@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Create service account key
gcloud iam service-accounts keys create ci-key.json \
  --iam-account=crystalshards-ci@$PROJECT_ID.iam.gserviceaccount.com

# Display the key (to add as GitHub secret)
cat ci-key.json
```

### 3. Configure GitHub Secrets

Add these secrets in GitHub repository settings:

1. Go to: `Settings → Secrets and variables → Actions`
2. Add repository secrets:
   - `GCP_PROJECT_ID`: Your GCP project ID
   - `GCP_SA_KEY`: Contents of `ci-key.json` from step 2
   - `GCP_REGION`: `us` (for multi-region Artifact Registry)

## Deployment Steps

### Step 1: Terraform Backend (Optional but Recommended)

Create a GCS bucket for Terraform state:

```bash
# Create bucket for Terraform state
gsutil mb -p $PROJECT_ID -l $REGION gs://$PROJECT_ID-terraform-state

# Enable versioning
gsutil versioning set on gs://$PROJECT_ID-terraform-state

# Configure backend
cat > terraform/backend.tf <<EOF
terraform {
  backend "gcs" {
    bucket = "$PROJECT_ID-terraform-state"
    prefix = "crystalshards"
  }
}
EOF
```

### Step 2: Terraform Variables

Create `terraform.tfvars`:

```bash
cd terraform

cat > terraform.tfvars <<EOF
project_id   = "$PROJECT_ID"
region       = "$REGION"
cluster_name = "crystalshards-cluster"
EOF
```

### Step 3: Terraform Init

```bash
cd terraform
terraform init
```

**Expected output**:

```
Terraform has been successfully initialized!
```

### Step 4: Terraform Plan

Review the infrastructure changes:

```bash
terraform plan
```

**What will be created**:

- GKE Autopilot cluster
- VPC network with Cloud NAT
- Artifact Registry repository (us-docker.pkg.dev)
- Kubernetes namespaces (4 apps + infrastructure + traefik-system)
- Kubernetes deployments (API servers + crystalshards worker)
- Kubernetes services
- PostgreSQL clusters (CloudNativePG)
- Redis cluster
- MinIO tenant
- Traefik ingress controller
- cert-manager
- Kubernetes secrets (generated)

**Review checklist**:

- [ ] Cluster region is correct
- [ ] Artifact Registry location is `us` (multi-region)
- [ ] All 4 app namespaces will be created
- [ ] PostgreSQL clusters configured for each app
- [ ] Resource requests/limits look appropriate

### Step 5: Apply Terraform

> **Warning**: This will create billable GCP resources

```bash
terraform apply
```

Review the plan one more time, then type `yes` to proceed.

**Expected duration**: 15-25 minutes (GKE cluster creation is slow)

**Monitor progress**:

```bash
# In another terminal, watch cluster creation
watch -n 10 "gcloud container clusters list --project=$PROJECT_ID"
```

### Step 6: Verify Infrastructure

After Terraform completes:

```bash
# Get cluster credentials
gcloud container clusters get-credentials crystalshards-cluster \
  --region=$REGION \
  --project=$PROJECT_ID

# Verify namespaces
kubectl get namespaces

# Expected output:
# crystalshards
# crystaldocs
# crystalgigs
# crystalbits
# infrastructure
# traefik-system

# Verify operators are running
kubectl get pods -n infrastructure

# Expected output:
# cert-manager pods (3)
# CNPG operator pod (1)
# redis-operator pod (1)
# minio-operator pod (1)

# Verify databases
kubectl get clusters.postgresql.cnpg.io -A

# Expected output (4 PostgreSQL clusters):
# NAME                  NAMESPACE        AGE
# crystalshards-db     crystalshards    5m
# crystaldocs-db       crystaldocs      5m
# crystalgigs-db       crystalgigs      5m
# crystalbits-db       crystalbits      5m

# Verify Artifact Registry
gcloud artifacts repositories list --project=$PROJECT_ID

# Expected output:
# NAME              FORMAT  LOCATION  ...
# crystalshards     DOCKER  us        ...
```

### Step 7: Trigger Docker Image Builds

After Terraform is applied, GitHub Actions will automatically build and push images:

1. The "Build and Push Docker Images" workflow will detect the Artifact Registry exists
2. Images will be built for all 4 apps (api + worker targets)
3. Images will be pushed to `us-docker.pkg.dev/$PROJECT_ID/crystalshards/*`

**Monitor build progress**:

```bash
# Watch GitHub Actions workflows
gh run list --limit 5

# View specific workflow logs
gh run view <run-id> --log
```

### Step 8: Verify Deployments

Once images are built, deployments should automatically start:

```bash
# Check all pods
kubectl get pods -A -l app.kubernetes.io/part-of=crystalshards

# Check deployment status
kubectl get deployments -A

# Check services
kubectl get services -A

# Check ingress
kubectl get ingress -A
```

**Wait for all pods to be Ready (1/1)**:

```bash
watch -n 5 "kubectl get pods -A | grep -E 'crystalshards|crystaldocs|crystalgigs|crystalbits'"
```

### Step 9: Test Endpoints

Get the external IP from Traefik ingress:

```bash
# Get ingress IP
kubectl get svc -n traefik-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Save it
export INGRESS_IP=$(kubectl get svc -n traefik-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

Test health endpoints:

```bash
# CrystalShards API
curl -H "Host: api.crystalshards.org" http://$INGRESS_IP/health

# CrystalDocs API
curl -H "Host: api.crystaldocs.org" http://$INGRESS_IP/health

# CrystalGigs API
curl -H "Host: api.crystalgigs.org" http://$INGRESS_IP/health

# CrystalBits API
curl -H "Host: api.crystalbits.org" http://$INGRESS_IP/health
```

**Expected response** (all should return 200 OK):

```json
{
  "status": "ok",
  "version": "0.1.0",
  "timestamp": "2025-10-07T10:00:00Z"
}
```

### Step 10: Configure DNS

Update DNS records to point to the ingress IP:

```
api.crystalshards.org  → A  → $INGRESS_IP
api.crystaldocs.org    → A  → $INGRESS_IP
api.crystalgigs.org    → A  → $INGRESS_IP
api.crystalbits.org    → A  → $INGRESS_IP
```

### Step 11: Run E2E Tests

Once DNS propagates (or using `/etc/hosts` override):

```bash
# In the tests directory
cd /workspaces/monorepo/tests/e2e

# Install dependencies
npm install

# Run tests
npm test
```

## Troubleshooting

### Issue: Terraform apply fails with "already exists"

**Symptom**: Resource already exists error

**Solution**: Import existing resource or remove from state

```bash
terraform import <resource_type>.<name> <resource_id>
```

### Issue: Pods stuck in "ImagePullBackOff"

**Symptom**: Pods can't pull images from Artifact Registry

**Root cause**: Images haven't been built yet, or registry permissions issue

**Solution 1**: Wait for CI to build images

```bash
gh run list --workflow="Build and Push Docker Images"
```

**Solution 2**: Build images manually

```bash
cd /workspaces/monorepo
make build-images
```

**Solution 3**: Check service account permissions

```bash
gcloud artifacts repositories get-iam-policy crystalshards \
  --project=$PROJECT_ID \
  --location=us
```

### Issue: PostgreSQL cluster not ready

**Symptom**: Pods show "Waiting for database to be ready"

**Solution**: Check CNPG cluster status

```bash
kubectl get clusters.postgresql.cnpg.io -A
kubectl describe cluster crystalshards-db -n crystalshards

# Check operator logs
kubectl logs -n infrastructure -l app.kubernetes.io/name=cloudnative-pg
```

### Issue: Ingress not getting external IP

**Symptom**: Traefik service stuck in "Pending"

**Solution**: Check GCP load balancer creation

```bash
# Check service
kubectl describe svc traefik -n traefik-system

# Check GCP load balancer
gcloud compute forwarding-rules list --project=$PROJECT_ID
```

### Issue: Certificate not issued

**Symptom**: HTTPS shows certificate error

**Solution**: Check cert-manager

```bash
kubectl get certificates -A
kubectl describe certificate -n crystalshards
kubectl logs -n infrastructure -l app.kubernetes.io/name=cert-manager
```

## Rollback Procedure

If deployment fails and you need to rollback:

### Option 1: Rollback Deployment

```bash
kubectl rollout undo deployment/crystalshards-api -n crystalshards
kubectl rollout status deployment/crystalshards-api -n crystalshards
```

### Option 2: Destroy Infrastructure

```bash
cd terraform
terraform destroy

# Confirm by typing: yes
```

**⚠️ Warning**: This will delete ALL infrastructure including databases. Data will be lost unless you have backups.

## Post-Deployment

### Set up monitoring

```bash
# Access Grafana
kubectl port-forward -n infrastructure svc/grafana 3000:80

# Open http://localhost:3000
# Default credentials: admin/admin
```

### Set up backups

PostgreSQL backups are configured via CNPG. Verify:

```bash
kubectl get backups.postgresql.cnpg.io -A
```

### Review costs

```bash
# Check GKE cluster costs
gcloud container clusters describe crystalshards-cluster \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format="get(totalResourceUsage)"
```

## Cost Estimates

**Monthly costs (estimated)**:

- GKE Autopilot cluster: $150-250
  - 4 API deployments (250m CPU, 512Mi RAM each)
  - 1 worker deployment (500m CPU, 1Gi RAM)
  - 5 databases (PostgreSQL via CNPG)
  - 1 Redis cluster
  - 1 MinIO tenant
- Networking (Cloud NAT, Load Balancer): $30-50
- Artifact Registry storage: $5-10
- **Total**: ~$185-310/month

**Cost optimization**:

- Autopilot only charges for pods that are running
- Consider reducing replicas in non-prod environments
- Use KEDA for scale-to-zero workloads
- Enable cluster autoscaler

## Support

- GitHub Issues: https://github.com/crystalshards/crystalshards-claude/issues
- Documentation: `/workspaces/monorepo/docs/`
- Runbooks: `/workspaces/monorepo/terraform/*.md`
