# Production Infrastructure Deployment Checklist

**Issue**: #24
**Date**: 2025-10-09
**Operator**: _____________
**Start Time**: _____________
**End Time**: _____________

## Pre-Deployment Checks

- [ ] Cluster-admin access verified: `kubectl auth can-i '*' '*' --all-namespaces`
- [ ] Terraform installed: `terraform version` (need v1.13+)
- [ ] kubectl configured: `kubectl cluster-info`
- [ ] Current directory: `cd /workspaces/monorepo/terraform`

## Step 1: Initialize Terraform (5 minutes)

### Option A: With GCS Access (Preferred)

- [ ] Run: `terraform init -reconfigure`
- [ ] Success? If yes, skip to Step 2. If no, try Option B.

### Option B: Local Backend (If GCS Fails)

- [ ] Create backend override file:
  ```bash
  cat > backend_override.tf <<'EOF'
  terraform {
    backend "local" {
      path = "terraform.tfstate"
    }
  }
  EOF
  ```
- [ ] Run: `terraform init -reconfigure -migrate-state`
- [ ] Verify: `ls -lh terraform.tfstate` (file should exist)

## Step 2: Plan Deployment (2-3 minutes)

- [ ] Run: `terraform plan -out=tfplan`
- [ ] Review plan output
- [ ] Verify these resources will be created:
  - [ ] 6 namespaces (claude, crystalshards, crystaldocs, crystalgigs, crystalbits, infrastructure)
  - [ ] ClusterRole: claude-agent-role
  - [ ] ClusterRoleBinding: claude-agent-binding
  - [ ] 3 Helm releases (cnpg-operator, redis-operator, minio-operator)
  - [ ] 4 PostgreSQL clusters
  - [ ] 1 Redis cluster
  - [ ] 1 MinIO tenant
  - [ ] Multiple Kubernetes deployments

## Step 3: Apply Deployment (10-15 minutes)

- [ ] Run: `terraform apply tfplan`
- [ ] Monitor progress (watch for errors)
- [ ] Wait for completion
- [ ] Success message shown: "Apply complete! Resources: X added, 0 changed, 0 destroyed."

## Step 4: Verify Infrastructure (5-10 minutes)

### Namespaces
- [ ] Run: `kubectl get namespaces`
- [ ] Verify all 6 namespaces exist

### Operators
- [ ] Run: `kubectl get pods -n infrastructure`
- [ ] Verify all operator pods are Running (may take 2-5 minutes)
  - [ ] cloudnativepg-operator
  - [ ] redis-operator
  - [ ] minio-operator

### PostgreSQL Clusters
- [ ] Run: `kubectl get cluster.postgresql.cnpg.io -A`
- [ ] Verify 4 clusters exist
- [ ] Run: `kubectl get cluster.postgresql.cnpg.io -A -o wide`
- [ ] Verify all clusters show PHASE=Ready (may take 5-10 minutes)

### Redis
- [ ] Run: `kubectl get redis -n infrastructure`
- [ ] Verify shared-redis exists
- [ ] Run: `kubectl get pods -n infrastructure | grep redis`
- [ ] Verify Redis pod is Running

### MinIO
- [ ] Run: `kubectl get tenant -n infrastructure`
- [ ] Verify shared-minio exists with STATE=Ready

### Agent RBAC
- [ ] Run: `kubectl get clusterrole claude-agent-role`
- [ ] Run: `kubectl get clusterrolebinding claude-agent-binding`
- [ ] Test permissions: `kubectl auth can-i list pods --as=system:serviceaccount:claude:default -A`
- [ ] Should return: yes

## Step 5: Verify Applications (3-5 minutes)

### Watch Application Pods
- [ ] Run: `watch -n 5 "kubectl get pods -A | grep -E 'crystalshards|crystaldocs|crystalgigs|crystalbits'"`
- [ ] Wait for all pods to show: 1/1 Running (may take 5-10 minutes)
- [ ] Press Ctrl+C when done

### Application Pod Status
- [ ] crystalshards-api: Running
- [ ] crystalshards-worker: Running
- [ ] crystaldocs-api: Running
- [ ] crystalgigs-api: Running
- [ ] crystalbits-api: Running

## Step 6: Test Health Endpoints

### Internal Health Checks
- [ ] CrystalShards: `kubectl exec -n crystalshards deploy/crystalshards-api -- curl -s localhost:5000/api/health`
- [ ] CrystalDocs: `kubectl exec -n crystaldocs deploy/crystaldocs-api -- curl -s localhost:5000/api/health`
- [ ] CrystalGigs: `kubectl exec -n crystalgigs deploy/crystalgigs-api -- curl -s localhost:5000/api/health`
- [ ] CrystalBits: `kubectl exec -n crystalbits deploy/crystalbits-api -- curl -s localhost:5000/api/health`

All should return: `{"status":"ok","version":"0.1.0","timestamp":"..."}`

### External Health Checks (if ingress configured)
- [ ] https://crystalshards.org/api/health
- [ ] https://crystaldocs.org/api/health
- [ ] https://crystalgigs.com/api/health
- [ ] https://crystalbits.org/api/health

## Step 7: Run Diagnostics

- [ ] Run: `bash /workspaces/monorepo/scripts/diagnose-deployments.sh`
- [ ] Review output for any errors
- [ ] All checks should pass

## Step 8: Document Results

- [ ] Update GitHub issue #24 with deployment results
- [ ] Include any errors or warnings encountered
- [ ] Note total deployment time
- [ ] Attach diagnostic script output if helpful

## Step 9: Close Issue

- [ ] Verify all applications are accessible and healthy
- [ ] Close GitHub issue #24
- [ ] Add comment: "Production infrastructure successfully deployed and verified"

## Troubleshooting

### Issue: Terraform init fails with GCS permissions
**Solution**: Use Option B (local backend)

### Issue: Helm releases fail to install
**Solution**: Check cluster connectivity and Helm version
```bash
kubectl cluster-info
helm version
```

### Issue: PostgreSQL clusters stuck in Pending
**Solution**: Check operator logs
```bash
kubectl logs -n infrastructure -l app.kubernetes.io/name=cloudnative-pg --tail=50
```

### Issue: Pods stuck in Pending
**Solution**: Check node resources and pod events
```bash
kubectl get nodes
kubectl get events -n crystalshards --sort-by='.lastTimestamp' | tail -20
```

### Issue: Health checks return 503
**Solution**: Check database and Redis connectivity
```bash
kubectl logs -n crystalshards deploy/crystalshards-api --tail=50
```

## Success Criteria

All items below must be checked before closing issue #24:

- [ ] All 6 namespaces exist
- [ ] All 3 operators are Running
- [ ] All 4 PostgreSQL clusters are Ready
- [ ] Redis cluster is Running
- [ ] MinIO tenant is Ready
- [ ] Agent RBAC permissions verified
- [ ] All 5 application pods are Running (1/1 Ready)
- [ ] All health endpoints return 200 OK
- [ ] Diagnostic script passes all checks
- [ ] No errors in pod logs

## Timeline

| Step | Estimated Time | Actual Time |
|------|----------------|-------------|
| Pre-checks | 2 min | _______ |
| Terraform init | 1 min | _______ |
| Terraform plan | 2 min | _______ |
| Terraform apply | 10-15 min | _______ |
| Verify infrastructure | 5-10 min | _______ |
| Verify applications | 3-5 min | _______ |
| Test health endpoints | 2 min | _______ |
| Run diagnostics | 2 min | _______ |
| Document results | 3 min | _______ |
| **TOTAL** | **30-45 min** | _______ |

## Notes

Use this space to document any issues, workarounds, or observations:

```
[Your notes here]
```

---

**Checklist prepared by**: SRE Agent
**Date**: 2025-10-09
**Reference**: GitHub Issue #24
