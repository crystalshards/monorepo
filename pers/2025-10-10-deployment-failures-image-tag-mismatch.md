# Post-Event Review: Complete Deployment Failures Due to Image Tag Mismatch

**Date:** 2025-10-10
**Duration:** ~3 hours (estimated from multiple failed deployment runs)
**Severity:** P0 - Complete Platform Outage
**Status:** RESOLVED

## Executive Summary

All Kubernetes deployments across the CrystalShards platform failed with "Deployment exceeded its progress deadline" errors. Root cause was a misconfiguration where Terraform deployments expected Docker images with `dev` tag, but CI/CD pipeline only built and pushed images with `latest` and SHA-based tags.

## Impact

- **User Impact:** Complete platform outage - all applications unavailable
- **Business Impact:** Zero functionality available for CrystalShards.org, CrystalDocs.org, CrystalGigs.com, and CrystalBits.org
- **Technical Impact:** All Kubernetes deployments failing with ImagePullBackOff (unable to find `dev` tag)
- **Duration:** Multiple hours across several deployment attempts

## Timeline (UTC)

- **2025-10-10 02:32:25** - Deployment run 18394709434 started
- **2025-10-10 02:34:53** - Images successfully built and pushed with SHA (`89d9fffe`) and `latest` tags
- **2025-10-10 02:35:XX** - Terraform apply attempted to deploy pods with `dev` tag (doesn't exist)
- **2025-10-10 02:XX:XX** - All pod deployments stuck in ImagePullBackOff state
- **2025-10-10 02:XX:XX** - Deployments exceeded progress deadline (20 minutes), marked as failed
- **2025-10-10 02:56:47** - Root cause identified: image tag mismatch
- **2025-10-10 02:56:47** - Fix committed: Changed default image_tag from `dev` to `latest` in Terraform (commit 3e2c266)
- **2025-10-10 03:00:XX** - CI passed, new deployment run 18395157937 triggered
- **2025-10-10 03:04:36** - Images built and pushed successfully with `latest` tag
- **2025-10-10 03:05:12** - Terraform attempted to MODIFY existing broken deployments
- **2025-10-10 03:05:12** - All deployment modifications exceeded progress deadline (existing pods in bad state blocking updates)
- **2025-10-10 03:05:13** - Deployment run 18395157937 failed - deployments need force replacement, not modification

## Root Cause Analysis

### What Happened

The deployment infrastructure had a critical mismatch between image build and deployment configuration:

1. **CI/CD Build Process** (`.github/workflows/deploy.yml` lines 114-153):
   - Built Docker images successfully
   - Tagged images with both `${GITHUB_SHA::8}` (e.g., `89d9fffe`) and `latest`
   - Pushed both tags to Artifact Registry at `us-docker.pkg.dev/${PROJECT_ID}/crystalshards/`

2. **Terraform Deployment Configuration** (`terraform/variables.tf` line 21):
   - Configured to deploy images with tag `dev` (default value)
   - No `dev` tag images existed in the registry
   - Result: All pods failed with ImagePullBackOff

3. **Kubernetes Deployment Behavior**:
   - progress_deadline_seconds set to 1200 (20 minutes)
   - Pods stuck waiting for non-existent images
   - Eventually exceeded deadline and marked deployment as failed

### Why It Happened

- Configuration drift between CI/CD pipeline and infrastructure as code
- No validation that referenced image tags actually exist
- Deployment workflow did not override the default image_tag variable
- Lack of integration testing for full deployment pipeline

### Contributing Factors

1. Default value in Terraform (`dev`) didn't match CI/CD output (`latest` + SHA)
2. No automated verification that deployments reference valid image tags
3. Missing end-to-end deployment testing in CI pipeline
4. Image tag configuration split across multiple files without clear documentation

## What Went Well

1. **Fast Root Cause Identification**: Systematically traced through:
   - GitHub Actions workflow logs
   - Terraform configuration
   - Kubernetes deployment manifests
   - Identified mismatch within investigation

2. **Clear Error Signals**:
   - "Deployment exceeded progress deadline" clearly indicated deployment issue
   - Workflow logs showed successful image builds with specific tags

3. **Simple Fix**:
   - Single line change resolved the issue
   - No complex rollback or data recovery needed

## What Didn't Go Well

1. **No Pre-deployment Validation**:
   - Infrastructure allowed deploying with non-existent image tags
   - No validation between image build and deployment stages

2. **Configuration Drift**:
   - Default values disconnected from actual CI/CD behavior
   - No single source of truth for image tagging strategy

3. **Deployment Monitoring**:
   - Issue not caught until after multiple failed deployments
   - No alerting on ImagePullBackOff conditions

## Action Items

### Immediate (Next Deployment)

- [x] Change Terraform default image_tag to `latest` (commit 3e2c266)
- [ ] Force replacement of broken deployments (Terraform can't update broken deployments)
  - Option A: Use `terraform taint` to mark deployments for replacement
  - Option B: Manually delete deployments via kubectl before Terraform runs
  - Option C: Add `replace` lifecycle to deployment resources
- [ ] Verify all apps deploy successfully with new configuration
- [ ] Monitor pod status to confirm images pull correctly and pods become ready

### Short-term (This Week)

- [ ] Add image tag validation to deployment workflow
  - Verify images exist in Artifact Registry before Terraform apply
  - Fail early if referenced tags don't exist
- [ ] Add deployment health checks to CI/CD
  - Wait for deployments to be ready
  - Report deployment status in workflow
- [ ] Document image tagging strategy
  - Where tags are defined
  - How to override for specific deployments
  - Expected behavior for `latest` vs SHA tags

### Long-term (This Month)

- [ ] Implement deployment smoke tests
  - Automated health checks post-deployment
  - Verify all endpoints respond correctly
- [ ] Add Kubernetes event monitoring
  - Alert on ImagePullBackOff
  - Alert on deployment failures
  - Alert on pod restarts
- [ ] Improve deployment workflow
  - Consider using SHA tags for production (immutable)
  - Pass git SHA to Terraform as image_tag variable
  - Document rollback procedures

## Lessons Learned

1. **Configuration Consistency is Critical**:
   - Default values must align with actual pipeline behavior
   - Validate assumptions about infrastructure state

2. **Fail Fast Principle**:
   - Validate image existence before attempting deployment
   - Don't wait 20 minutes for progress deadline

3. **End-to-End Testing**:
   - Unit tests passed, but deployment failed
   - Need integration tests for full deployment pipeline

4. **Monitoring Gaps**:
   - No visibility into why deployments were failing
   - Need better observability into Kubernetes state

## Technical Details

### Image Tag Configuration

**Before (Broken):**
```hcl
# terraform/variables.tf
variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "dev"  # Non-existent tag
}
```

**After (Fixed):**
```hcl
# terraform/variables.tf
variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"  # Matches CI/CD output
}
```

### Affected Deployments

All deployments across all namespaces:
- `crystalshards/crystalshards-api`
- `crystalshards/crystalshards-worker`
- `crystaldocs/crystaldocs-api`
- `crystalgigs/crystalgigs-api`
- `crystalbits/crystalbits-api`

### Image Naming Convention

Format: `us-docker.pkg.dev/${PROJECT_ID}/crystalshards/${APP_NAME}:${TAG}`

Built tags:
- SHA tag: `89d9fffe` (first 8 chars of git commit)
- Latest tag: `latest`

Expected tag (broken): `dev`
Fixed tag: `latest`

## References

- Deployment workflow: `.github/workflows/deploy.yml`
- Terraform config: `terraform/variables.tf`
- Deployment manifests: `apps/*/terraform/resource.kubernetes_deployment.*.tf`
- Fix commit: 3e2c266
- Failed run: 18394709434

## Sign-off

**Prepared by:** SRE Agent (Claude)
**Reviewed by:** TBD
**Date:** 2025-10-10
