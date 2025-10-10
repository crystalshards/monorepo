#!/bin/bash
# Force update secrets to apply database connectivity fix
# This script manually forces Terraform to recreate the kubernetes_secret resources
# so that they pick up the corrected DATABASE_URL with username from CNPG secrets.
#
# Background:
# - Commit 6133edc fixed DATABASE_URL to read username from CNPG secrets
# - However, Terraform doesn't detect changes in data source interpolations
# - The lifecycle triggers added in this commit will prevent future issues
# - This script is a ONE-TIME fix to apply the change to production
#
# Usage:
#   cd /workspaces/monorepo/terraform
#   bash FORCE_UPDATE_SECRETS.sh

set -e

echo "=== Force Update Application Secrets ==="
echo ""
echo "This script forces Terraform to recreate all application secrets"
echo "to apply the database connectivity fix from commit 6133edc."
echo ""

# Check we're in the right directory
if [ ! -f "module.applications.tf" ]; then
  echo "Error: Must be run from /workspaces/monorepo/terraform directory"
  exit 1
fi

# Check Terraform is initialized
if [ ! -d ".terraform" ]; then
  echo "Initializing Terraform..."
  terraform init
fi

echo "Step 1: Planning secret replacement..."
echo ""

# Plan with force-replace for all application secrets
terraform plan \
  -var="project_id=${GCP_PROJECT_ID:-crystalshards-platform}" \
  -var="region=us-central1" \
  -replace='module.applications.module.crystalshards.kubernetes_secret.crystalshards_secrets' \
  -replace='module.applications.module.crystaldocs.kubernetes_secret.crystaldocs_secrets' \
  -replace='module.applications.module.crystalgigs.kubernetes_secret.crystalgigs_secrets' \
  -replace='module.applications.module.crystalbits.kubernetes_secret.crystalbits_secrets' \
  -out=tfplan-secret-update

echo ""
echo "Step 2: Reviewing plan..."
echo ""
echo "The plan should show the following secrets will be REPLACED:"
echo "  - module.applications.module.crystalshards.kubernetes_secret.crystalshards_secrets"
echo "  - module.applications.module.crystaldocs.kubernetes_secret.crystaldocs_secrets"
echo "  - module.applications.module.crystalgigs.kubernetes_secret.crystalgigs_secrets"
echo "  - module.applications.module.crystalbits.kubernetes_secret.crystalbits_secrets"
echo ""

# Prompt for confirmation
read -p "Do you want to apply these changes? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Aborted. No changes were applied."
  rm -f tfplan-secret-update
  exit 1
fi

echo ""
echo "Step 3: Applying changes..."
echo ""

terraform apply tfplan-secret-update

echo ""
echo "Step 4: Waiting for pods to pick up new secrets..."
echo ""
sleep 10

echo "Step 5: Triggering pod rollout to reload secrets..."
echo ""

# Note: We can't run kubectl commands from here due to permissions
# This will be handled by the deployment workflow or manually

echo "Secrets have been updated in Kubernetes!"
echo ""
echo "Next steps:"
echo "1. Wait for pods to automatically restart (may take a few minutes)"
echo "2. Or manually restart deployments:"
echo "   kubectl rollout restart deployment/crystalshards-api -n crystalshards"
echo "   kubectl rollout restart deployment/crystalshards-workers -n crystalshards"
echo "   kubectl rollout restart deployment/crystaldocs-api -n crystaldocs"
echo "   kubectl rollout restart deployment/crystalgigs-api -n crystalgigs"
echo "   kubectl rollout restart deployment/crystalbits-api -n crystalbits"
echo ""
echo "3. Verify health endpoints:"
echo "   curl https://crystalshards.org/api/health | jq"
echo "   curl https://crystaldocs.org/api/health | jq"
echo "   curl https://crystalgigs.com/api/health | jq"
echo "   curl https://crystalbits.org/api/health | jq"
echo ""
echo "Done!"
