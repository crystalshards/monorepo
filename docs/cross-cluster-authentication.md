# Cross-Cluster Authentication for CrystalShards Agent

This document describes how the CrystalShards agent authenticates to the production cluster from a separate agent cluster using service account tokens.

## Architecture

The agent runs in a dedicated cluster (waldrip.net) and needs read-only access to the production cluster (crystalshards-cluster) to monitor deployments, inspect resources, and troubleshoot issues.

### Components

1. **Production Cluster**: `crystalshards-cluster` in `us-central1`
   - Contains all production workloads (CrystalShards, CrystalDocs, etc.)
   - Has service account `claude-agent` with read-only RBAC permissions
   - Generates time-limited tokens for authentication

2. **Agent Cluster**: `gke_waldrip-net_us-central1-a_cluster-1`
   - Runs the CrystalShards agent pod
   - Stores production cluster credentials as a Kubernetes Secret
   - Agent pod mounts this Secret to access production cluster

3. **Service Account Token**: 30-day bound token
   - Created from `claude-agent` service account in production
   - Embedded in kubeconfig file
   - Provides read-only access to production resources

## Manual Setup (Part 1)

For immediate setup or troubleshooting, follow these manual steps:

### Prerequisites

- `gcloud` CLI authenticated with appropriate permissions
- `kubectl` CLI installed
- Access to both production and agent clusters
- `envsubst` installed (from `gettext` package)

### Step-by-Step

```bash
# 1. Authenticate to production cluster
gcloud container clusters get-credentials crystalshards-cluster --region=us-central1

# 2. Verify RBAC resources exist
kubectl get sa claude-agent -n claude
kubectl get clusterrole claude-agent-role
kubectl get clusterrolebinding claude-agent-binding

# 3. Extract cluster information
PROD_ENDPOINT=$(gcloud container clusters describe crystalshards-cluster \
  --region=us-central1 --format='value(endpoint)')
PROD_CA=$(gcloud container clusters describe crystalshards-cluster \
  --region=us-central1 --format='value(masterAuth.clusterCaCertificate)')

# 4. Create 30-day service account token
PROD_TOKEN=$(kubectl create token claude-agent -n claude --duration=720h)

# 5. Build kubeconfig using envsubst
cat > /tmp/kubeconfig-template.yaml << 'EOF'
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

export PROD_CA PROD_ENDPOINT PROD_TOKEN
envsubst < /tmp/kubeconfig-template.yaml > /tmp/prod-kubeconfig.yaml

# 6. Test kubeconfig locally
KUBECONFIG=/tmp/prod-kubeconfig.yaml kubectl get pods -A

# 7. Switch to agent cluster
kubectl config use-context gke_waldrip-net_us-central1-a_cluster-1

# 8. Create namespace if needed
kubectl get ns claude || kubectl create ns claude

# 9. Create Secret in agent cluster
kubectl create secret generic prod-kubeconfig -n claude \
  --from-file=config=/tmp/prod-kubeconfig.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

# 10. Verify Secret was created
kubectl get secret prod-kubeconfig -n claude
```

### Testing Access

Create a test pod to verify the configuration:

```bash
# Create test pod with kubectl
kubectl run test-agent --image=bitnami/kubectl:latest --restart=Never -n claude \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "test-agent",
      "image": "bitnami/kubectl:latest",
      "command": ["sleep", "3600"],
      "volumeMounts": [{
        "name": "kubeconfig",
        "mountPath": "/root/.kube",
        "readOnly": true
      }]
    }],
    "volumes": [{
      "name": "kubeconfig",
      "secret": {
        "secretName": "prod-kubeconfig"
      }
    }]
  }
}'

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/test-agent -n claude --timeout=60s

# Test cluster access
kubectl exec test-agent -n claude -- \
  sh -c 'KUBECONFIG=/root/.kube/config kubectl cluster-info'

kubectl exec test-agent -n claude -- \
  sh -c 'KUBECONFIG=/root/.kube/config kubectl get pods -A | head -10'

kubectl exec test-agent -n claude -- \
  sh -c 'KUBECONFIG=/root/.kube/config kubectl get nodes'

# Cleanup test pod
kubectl delete pod test-agent -n claude
```

## Automated Setup (Part 2)

The automation script handles all the manual steps above and integrates with agent deployment.

### Script: `scripts/setup-prod-cluster-access.sh`

This script:
1. Authenticates to production cluster
2. Extracts cluster endpoint and CA certificate
3. Verifies service account exists
4. Creates fresh 30-day token
5. Builds kubeconfig with `envsubst`
6. Verifies kubeconfig works
7. Switches to agent cluster
8. Creates/updates Secret

### Usage

```bash
# Run standalone
./scripts/setup-prod-cluster-access.sh

# With custom agent cluster context
AGENT_CLUSTER_CONTEXT=my-cluster ./scripts/setup-prod-cluster-access.sh
```

### Integration with Agent Deployment

The script is automatically called by `start-remote-agent.sh` before deploying the agent pod:

```bash
# In start-remote-agent.sh
./scripts/setup-prod-cluster-access.sh
```

This ensures the agent always has fresh credentials when deployed.

## Token Rotation

Service account tokens have a 30-day expiration. To rotate the token:

### Automatic Rotation

Re-run the deployment script, which will fetch a fresh token:

```bash
./start-remote-agent.sh
```

### Manual Rotation

If the agent pod is already running and you just need to refresh credentials:

```bash
# Run the automation script
./scripts/setup-prod-cluster-access.sh

# Restart the agent pod to pick up new Secret
kubectl delete pod <agent-pod-name> -n claude
```

### Monitoring Token Expiration

The token's expiration time is encoded in the JWT. To decode:

```bash
# Extract token from Secret
TOKEN=$(kubectl get secret prod-kubeconfig -n claude -o jsonpath='{.data.config}' | \
  base64 -d | grep 'token:' | awk '{print $2}')

# Decode JWT (requires jq)
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '.exp'

# Convert to human-readable date
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq -r '.exp' | \
  xargs -I{} date -r {}
```

## RBAC Permissions

The `claude-agent` service account has read-only access to production cluster resources:

### Allowed Operations

- List and get: pods, deployments, services, configmaps, secrets
- View: nodes, namespaces, events
- Inspect: custom resources (PostgreSQL clusters, Redis, MinIO)
- Monitor: ingresses, certificates, service monitors

### Denied Operations

- Create, update, delete any resources
- Execute into pods
- Modify RBAC
- Access secrets (can list, but values are read-only)

See `terraform/modules/agent/main.tf` for full RBAC configuration.

## Troubleshooting

### Token Expired

**Symptoms**: Authentication errors, "Unauthorized" messages

**Solution**:
```bash
./scripts/setup-prod-cluster-access.sh
kubectl rollout restart deployment <agent-deployment> -n claude
```

### Secret Not Found

**Symptoms**: Pod fails to start with "Secret not found" error

**Solution**:
```bash
# Ensure Secret exists
kubectl get secret prod-kubeconfig -n claude

# If missing, run automation
./scripts/setup-prod-cluster-access.sh
```

### Permission Denied

**Symptoms**: "Forbidden" errors when accessing resources

**Solution**:
```bash
# Verify RBAC in production cluster
kubectl config use-context gke_crystalshards-org_us-central1_crystalshards-cluster
kubectl get clusterrole claude-agent-role
kubectl get clusterrolebinding claude-agent-binding

# If missing, apply Terraform
cd terraform
terraform apply -target=module.agent
```

### Wrong Cluster Context

**Symptoms**: Accessing wrong cluster or no resources found

**Solution**:
```bash
# Inside pod, verify kubeconfig
kubectl exec <agent-pod> -n claude -- cat /root/.kube/config | grep server

# Should show: https://136.112.216.90 (production endpoint)
```

### kubectl Not Found in Pod

**Symptoms**: `kubectl: command not found` in agent pod

**Solution**: Ensure the agent pod image includes `kubectl`, or install it in the pod:

```bash
# In Dockerfile or pod startup script
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/
```

## Security Considerations

### Token Security

- Tokens are stored in Kubernetes Secrets (base64 encoded, not encrypted at rest by default)
- Use encryption at rest for Secrets in production environments
- Rotate tokens before expiration
- Monitor token usage via audit logs

### Network Security

- Production cluster API endpoint is public (136.112.216.90)
- Consider using VPC peering or Private GKE clusters for enhanced security
- Use Network Policies to restrict agent pod network access

### RBAC Least Privilege

- Service account has only read permissions
- Cannot modify or delete resources
- Cannot execute commands in pods
- Regular RBAC audits recommended

## Future Enhancements

### Token Refresh Sidecar

Create a sidecar container that automatically refreshes tokens before expiration:

```yaml
- name: token-refresher
  image: bitnami/kubectl:latest
  command:
  - sh
  - -c
  - |
    while true; do
      sleep 20h  # Refresh 4 hours before expiration
      # Fetch new token and update Secret
      # (requires additional RBAC for agent cluster)
    done
```

### Workload Identity Federation

For GKE-to-GKE authentication, consider using Workload Identity:
- Eliminates manual token management
- Automatic credential rotation
- More secure than long-lived tokens

### HashiCorp Vault Integration

Store and rotate tokens using Vault:
- Centralized secret management
- Automatic token rotation
- Audit trail of token access

## References

- [Kubernetes Service Account Tokens](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [kubectl Configuration](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)

## Support

For issues or questions:
- Check troubleshooting section above
- Review RBAC configuration in Terraform
- Verify both cluster contexts are accessible
- Contact DevOps team if issues persist
