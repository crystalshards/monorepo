# Terraform State Lock Resolution

## Issue Detected

**Date:** 2025-10-09
**Lock ID:** 1760020100905736
**Status:** Active lock from stuck workflow

## Cause

Multiple deployment workflows were triggered without concurrency controls, causing:
1. Workflow 18379587131 started at 2025-10-09T14:25:47Z
2. Subsequent workflows failed with state lock errors
3. First workflow appears stuck (no updates since 2025-10-09T14:27:56Z)

## Resolution Steps

### Step 1: Cancel Stuck Workflow

```bash
gh run cancel 18379587131
```

This will cancel the stuck workflow that's been running for over 2 hours.

### Step 2: Force Unlock Terraform State

Use the terraform-unlock workflow to remove the stale lock:

```bash
gh workflow run terraform-unlock.yml -f lock_id=1760020100905736
```

Or manually via GitHub UI:
1. Go to Actions → Force Unlock Terraform State
2. Click "Run workflow"
3. Enter Lock ID: `1760020100905736`
4. Click "Run workflow"

### Step 3: Verify Fix

After unlocking, verify the state is accessible:

```bash
cd terraform
terraform init
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

## Prevention Measures Implemented

### 1. Concurrency Controls Added

**File:** `.github/workflows/deploy.yml`
```yaml
concurrency:
  group: terraform-deploy-${{ github.ref }}
  cancel-in-progress: false
```

**File:** `.github/workflows/terraform-unlock.yml`
```yaml
concurrency:
  group: terraform-unlock
  cancel-in-progress: false
```

These settings ensure:
- Only one deployment workflow runs at a time per branch
- New workflows queue instead of running concurrently
- No automatic cancellation (prevents partial applies)

### 2. How It Works

- `group`: Groups related workflows together
- `cancel-in-progress: false`: Queues new runs instead of canceling active ones
- This prevents multiple Terraform operations from conflicting

## Testing the Fix

1. Trigger multiple deployments in quick succession
2. Verify only one runs at a time
3. Verify subsequent runs queue and wait
4. Confirm no more state lock errors

## Lock Information Summary

```
Lock ID:        1760020100905736
Operation:      OperationTypeApply
Who:            runner@runnervmwhb2z
Path:           gs://crystalshards-org-terraform-state/terraform/state/default.tflock
Created:        ~2025-10-09T14:25:47Z (from workflow start time)
Workflow Run:   18379587131
```

## Related Workflows

- Primary workflow: `.github/workflows/deploy.yml`
- Unlock workflow: `.github/workflows/terraform-unlock.yml`
- Backend config: `terraform/terraform.tf`

## Best Practices Going Forward

1. Always check for running workflows before manual deployments
2. Use the unlock workflow only for genuinely stuck locks
3. Monitor workflow run times (timeout: 15-20 minutes is normal)
4. If a workflow runs > 30 minutes, it's likely stuck
5. Cancel stuck workflows before unlocking state

## Verification Commands

```bash
# Check for running workflows
gh run list --workflow=deploy.yml --status in_progress

# Check recent failures
gh run list --workflow=deploy.yml --limit 5

# View specific run details
gh run view RUN_ID --log-failed

# Cancel a stuck run
gh run cancel RUN_ID
```
