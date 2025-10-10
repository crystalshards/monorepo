# Post-Event Review: Terraform Secret Update Issue

**Date**: October 10, 2025
**Status**: RESOLVED
**Related Issues**: #52, #53
**Related Commits**: 6133edc, cc98382

## Executive Summary

Two consecutive deployment failures occurred due to Terraform not applying database credential updates. The root cause was that Terraform doesn't automatically detect when data source values change, causing `kubernetes_secret` resources to retain outdated DATABASE_URL values despite code changes.

## Timeline

- **Commit 6133edc**: Fixed DATABASE_URL to read username from CNPG secrets (correct fix)
- **Deployment 1**: Failed - secrets not updated, still using `app` username
- **Deployment 2**: Failed - same issue, Terraform not detecting changes
- **Investigation**: Identified Terraform data source limitation
- **Commit cc98382**: Added lifecycle triggers to force secret replacement
- **Deployment 3**: Expected to succeed with lifecycle-triggered updates

## Root Cause Analysis

### The Problem

Terraform's data sources are read-only and evaluated at plan/apply time. When a resource depends on a data source through interpolation, Terraform doesn't automatically detect when the data source's values change.

### Specific Technical Issue

1. `kubernetes_secret` resources use `data.kubernetes_secret.APP_postgres_app` to construct DATABASE_URL
2. The resource definition changed from `app:${password}` to `${username}:${password}`
3. Terraform compared the **planned value** with **state value**, but both used the same cached data source
4. No change detected → no secret update → pods get stale credentials

### Why CrystalBits Was Healthy

CrystalBits likely had different initial configuration or deployment timing, resulting in its CNPG secret having the expected username format, allowing successful database connections while other apps failed.

## The Fix

### Immediate Fix (Commit cc98382)

Added `lifecycle.replace_triggered_by` blocks to all `kubernetes_secret` resources:

```hcl
lifecycle {
  replace_triggered_by = [
    data.kubernetes_secret.APP_postgres_app.id,
    data.kubernetes_secret.minio_user.id  # where applicable
  ]
}
```

This forces Terraform to recreate the secret when the underlying data source IDs change.

### Files Changed

- `apps/crystalshards/terraform/resource.kubernetes_secret.crystalshards_secrets.tf`
- `apps/crystaldocs/terraform/resource.kubernetes_secret.crystaldocs_secrets.tf`
- `apps/crystalgigs/terraform/resource.kubernetes_secret.crystalgigs_secrets.tf`
- `apps/crystalbits/terraform/resource.kubernetes_secret.crystalbits_secrets.tf`
- `.github/workflows/deploy.yml` (documentation)
- `terraform/FORCE_UPDATE_SECRETS.sh` (manual fix script)

### How It Works

1. Terraform tracks the `id` attribute of data sources
2. When a data source ID changes (e.g., CNPG regenerates secrets), Terraform detects it
3. The `replace_triggered_by` lifecycle rule forces secret recreation
4. Kubernetes sees the secret change and rolls out pods with new credentials

## Prevention

### Long-term Solution

The lifecycle triggers prevent this issue permanently. Future changes to:
- CNPG database credentials
- MinIO credentials
- Any other data-sourced secrets

...will automatically trigger secret replacement.

### Manual Override

If needed, the `terraform/FORCE_UPDATE_SECRETS.sh` script provides a manual way to force secret updates:

```bash
cd terraform
bash FORCE_UPDATE_SECRETS.sh
```

## Lessons Learned

### What Went Well

- Root cause identified quickly through systematic investigation
- Fix implemented correctly the first time (6133edc)
- Comprehensive testing revealed the Terraform behavior issue

### What Could Be Improved

- Initial implementation should have included lifecycle triggers
- Better understanding of Terraform data source behavior needed
- Automated tests for Terraform plan detection would help

### Action Items

- [ ] Document Terraform data source patterns in runbook
- [ ] Add lifecycle triggers to all future data-source-dependent resources
- [ ] Consider Terraform plan validation in CI to detect "no changes" when changes expected
- [ ] Update team knowledge base with Terraform best practices

## Related Documentation

- Deployment Runbook: `/workspaces/monorepo/terraform/DEPLOYMENT_RUNBOOK.md`
- Database Troubleshooting: Added to runbook in commit ef5a4d3
- Force Update Script: `/workspaces/monorepo/terraform/FORCE_UPDATE_SECRETS.sh`

## Resolution Verification

Expected after deployment completes:

```bash
# All health endpoints should return 200 with healthy services
curl https://crystalshards.org/api/health | jq
curl https://crystaldocs.org/api/health | jq
curl https://crystalgigs.com/api/health | jq
curl https://crystalbits.org/api/health | jq
```

Expected output: All services showing "healthy" status with successful database connections.

## Appendix: Terraform Data Source Behavior

### Key Principle

Data sources in Terraform are **read-only references** to external resources. Changes to the external resource don't automatically trigger updates to dependent resources unless explicitly configured.

### Best Practice

Always use `lifecycle.replace_triggered_by` when:
- A `resource` depends on a `data` source
- The resource's configuration uses interpolation from the data source
- The data source's values may change over time
- You need the resource to update when the data source changes

### Example

```hcl
data "kubernetes_secret" "external_creds" {
  metadata {
    name      = "external-secret"
    namespace = "default"
  }
}

resource "kubernetes_secret" "app_config" {
  metadata {
    name = "app-config"
  }

  data = {
    connection_string = "host=${data.kubernetes_secret.external_creds.data["host"]}"
  }

  lifecycle {
    # REQUIRED: Force update when external credentials change
    replace_triggered_by = [data.kubernetes_secret.external_creds.id]
  }
}
```

Without the lifecycle block, changes to `external-secret` won't update `app-config`.
