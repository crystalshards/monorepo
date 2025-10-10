#!/bin/bash
set -e

# Script to automate production cluster access from agent cluster
# This creates a service account token and kubeconfig for cross-cluster authentication

echo "🔐 Setting up production cluster access for agent..."
echo "=================================================="

# Configuration
PROD_CLUSTER="crystalshards-cluster"
PROD_REGION="us-central1"
PROD_NAMESPACE="claude"
PROD_SERVICE_ACCOUNT="claude-agent"
AGENT_CLUSTER_CONTEXT="${AGENT_CLUSTER_CONTEXT:-gke_waldrip-net_us-central1-a_cluster-1}"
AGENT_NAMESPACE="claude"
SECRET_NAME="prod-kubeconfig"
TOKEN_DURATION="24h"

echo ""
echo "Production cluster: $PROD_CLUSTER"
echo "Production region: $PROD_REGION"
echo "Service account: $PROD_SERVICE_ACCOUNT"
echo "Agent cluster: $AGENT_CLUSTER_CONTEXT"
echo "Token duration: $TOKEN_DURATION"
echo ""

# Step 1: Get production cluster credentials
echo "📡 Authenticating to production cluster..."
gcloud container clusters get-credentials "$PROD_CLUSTER" --region="$PROD_REGION" --quiet

# Step 2: Extract cluster information
echo "🔍 Extracting cluster information..."
PROD_ENDPOINT=$(gcloud container clusters describe "$PROD_CLUSTER" --region="$PROD_REGION" --format='value(endpoint)')
PROD_CA=$(gcloud container clusters describe "$PROD_CLUSTER" --region="$PROD_REGION" --format='value(masterAuth.clusterCaCertificate)')

if [ -z "$PROD_ENDPOINT" ] || [ -z "$PROD_CA" ]; then
    echo "❌ Failed to extract cluster information"
    exit 1
fi

echo "   Endpoint: $PROD_ENDPOINT"
echo "   CA certificate extracted"

# Step 3: Verify service account exists
echo "🔍 Verifying service account exists..."
if ! kubectl get sa "$PROD_SERVICE_ACCOUNT" -n "$PROD_NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Service account $PROD_SERVICE_ACCOUNT not found in namespace $PROD_NAMESPACE"
    echo "   Please apply Terraform RBAC configuration first"
    exit 1
fi

echo "   Service account exists"

# Step 4: Create fresh service account token
echo "🎟️  Creating service account token (valid for $TOKEN_DURATION)..."
PROD_TOKEN=$(kubectl create token "$PROD_SERVICE_ACCOUNT" -n "$PROD_NAMESPACE" --duration="$TOKEN_DURATION")

if [ -z "$PROD_TOKEN" ]; then
    echo "❌ Failed to create service account token"
    exit 1
fi

echo "   Token created successfully"

# Step 5: Build kubeconfig using envsubst
echo "📝 Building kubeconfig..."
TEMP_KUBECONFIG=$(mktemp)
FINAL_KUBECONFIG=$(mktemp)

cat > "$TEMP_KUBECONFIG" << 'EOF'
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${PROD_CA}
    server: https://${PROD_ENDPOINT}
  name: crystalshards-cluster
contexts:
- context:
    cluster: crystalshards-cluster
    user: claude-agent
  name: crystalshards-cluster
current-context: crystalshards-cluster
users:
- name: claude-agent
  user:
    token: ${PROD_TOKEN}
EOF

# Use envsubst to replace variables
export PROD_CA PROD_ENDPOINT PROD_TOKEN
envsubst < "$TEMP_KUBECONFIG" > "$FINAL_KUBECONFIG"

echo "   Kubeconfig created at $FINAL_KUBECONFIG"

# Step 6: Verify kubeconfig works
echo "✅ Verifying kubeconfig works..."
if ! KUBECONFIG="$FINAL_KUBECONFIG" kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Kubeconfig verification failed"
    rm -f "$TEMP_KUBECONFIG" "$FINAL_KUBECONFIG"
    exit 1
fi

echo "   Kubeconfig verified"

# Step 7: Switch to agent cluster
echo "🔄 Switching to agent cluster..."
kubectl config use-context "$AGENT_CLUSTER_CONTEXT"

# Step 8: Ensure namespace exists
echo "🔍 Ensuring namespace exists in agent cluster..."
if ! kubectl get ns "$AGENT_NAMESPACE" >/dev/null 2>&1; then
    echo "   Creating namespace $AGENT_NAMESPACE..."
    kubectl create ns "$AGENT_NAMESPACE"
fi

# Step 9: Create or update Secret in agent cluster
echo "📦 Creating/updating Secret in agent cluster..."
kubectl create secret generic "$SECRET_NAME" \
    -n "$AGENT_NAMESPACE" \
    --from-file=config="$FINAL_KUBECONFIG" \
    --dry-run=client -o yaml | kubectl apply -f -

# Clean up temporary files
rm -f "$TEMP_KUBECONFIG" "$FINAL_KUBECONFIG"

echo ""
echo "✅ Production cluster access configured successfully!"
echo ""
echo "Secret '$SECRET_NAME' created in namespace '$AGENT_NAMESPACE'"
echo ""
echo "To use in a pod, mount the secret as a volume:"
echo ""
cat << 'PODSPEC'
  volumeMounts:
  - name: prod-kubeconfig
    mountPath: /root/.kube
    readOnly: true

  volumes:
  - name: prod-kubeconfig
    secret:
      secretName: prod-kubeconfig
PODSPEC
echo ""
echo "Then use: KUBECONFIG=/root/.kube/config kubectl ..."
echo ""
echo "⚠️  Token expires in $TOKEN_DURATION"
echo "    Re-run this script to refresh the token before expiration"
echo ""
