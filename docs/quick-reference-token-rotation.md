# Quick Reference: Token Rotation

## When to Rotate

- Every 30 days (token expiration)
- Before deploying agent pod
- After RBAC changes in production cluster
- When authentication errors occur

## Quick Commands

### Automatic Rotation (Recommended)

```bash
# Full agent redeployment (includes token refresh)
./start-remote-agent.sh
```

### Manual Rotation Only

```bash
# Just refresh credentials without redeploying pod
./scripts/setup-prod-cluster-access.sh

# Restart agent pod to pick up new credentials
kubectl delete pod <agent-pod> -n claude
```

### Check Token Expiration

```bash
# Extract and decode token
kubectl get secret prod-kubeconfig -n claude -o jsonpath='{.data.config}' | \
  base64 -d | grep 'token:' | awk '{print $2}' | \
  cut -d. -f2 | base64 -d 2>/dev/null | jq -r '.exp | todate'
```

### Verify Access

```bash
# From your local machine
KUBECONFIG=<(kubectl get secret prod-kubeconfig -n claude -o jsonpath='{.data.config}' | base64 -d) \
  kubectl get pods -A | head -5

# From inside agent pod
kubectl exec <agent-pod> -n claude -- \
  sh -c 'KUBECONFIG=/root/.kube/config kubectl get nodes'
```

## Troubleshooting One-Liners

```bash
# Check if Secret exists
kubectl get secret prod-kubeconfig -n claude >/dev/null && echo "✅ Secret exists" || echo "❌ Secret missing"

# Check if service account exists in production
kubectl --context gke_crystalshards-org_us-central1_crystalshards-cluster \
  get sa claude-agent -n claude >/dev/null && echo "✅ Service account exists" || echo "❌ Service account missing"

# Test production cluster access
KUBECONFIG=<(kubectl get secret prod-kubeconfig -n claude -o jsonpath='{.data.config}' | base64 -d) \
  kubectl cluster-info && echo "✅ Access working" || echo "❌ Access failed"
```

## Emergency Recovery

If everything breaks:

```bash
# 1. Re-run automation
./scripts/setup-prod-cluster-access.sh

# 2. If that fails, manual setup
gcloud container clusters get-credentials crystalshards-cluster --region=us-central1
TOKEN=$(kubectl create token claude-agent -n claude --duration=720h)
# ... see full manual steps in cross-cluster-authentication.md

# 3. Verify RBAC in production
kubectl get sa claude-agent -n claude
kubectl get clusterrole claude-agent-role
kubectl get clusterrolebinding claude-agent-binding

# 4. If RBAC missing, apply Terraform
cd terraform && terraform apply -target=module.agent
```

## Monitoring Setup

Add this to your monitoring/alerting:

```bash
# Cron job to check token expiration (runs daily)
0 12 * * * kubectl get secret prod-kubeconfig -n claude -o jsonpath='{.data.config}' | \
  base64 -d | grep 'token:' | awk '{print $2}' | cut -d. -f2 | base64 -d 2>/dev/null | \
  jq -r 'if (.exp - now) < 86400 then "WARNING: Token expires in less than 1 day" else empty end'
```

## File Locations

- Automation script: `scripts/setup-prod-cluster-access.sh`
- Agent deployment: `start-remote-agent.sh`
- Pod manifest: `kubernetes-dev-pod.yaml`
- RBAC config: `terraform/modules/agent/main.tf`
- Full docs: `docs/cross-cluster-authentication.md`
