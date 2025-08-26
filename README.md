# CrystalShards Autonomous Development

An autonomous agent that builds CrystalShards.org and CrystalDocs.org - a comprehensive Crystal language package registry and documentation platform.

## Quick Start

```bash
# Set your credentials
export CLAUDE_CODE_OAUTH_TOKEN="your-claude-api-key"
export GITHUB_TOKEN="your-github-token"

# Launch the agent (uses kubernetes-dev-pod.yaml)
./remote.sh

# Watch it work
kubectl logs -f crystalshards-agent -n claude

# Optional: Use custom settings
GIT_URL="https://github.com/yourfork/crystalshards-claude.git" \
GIT_BRANCH="feature/my-branch" \
POD_NAME="my-agent" \
./remote.sh
```

The script will:

- Create namespace, PVC, secrets, and pod from kubernetes-dev-pod.yaml
- Substitute your API keys automatically
- Wait for pod readiness
- Optionally tail logs

## Philosophy

Following the "less is more" approach - a simple prompt drives continuous development with frequent commits.

## What It Builds

1. **CrystalShards.org** - Package registry like rubygems.org
2. **CrystalDocs.org** - Documentation platform like docs.rs
3. **CrystalGigs.com** - Paid job board for Crystal developers

Features:

- Full-text search, dependency graphs, download stats
- Automated documentation generation in sandboxed K8s jobs
- Stripe integration for paid job postings
- Everything runs in-cluster (no external cloud services)
- KEDA autoscaling (scale to zero when idle)
- Cost-optimized with Heroku-style scale-on-request

## Files

- `PROMPT.md` - Simple prompt that guides the agent
- `develop.sh` - Continuous loop: prompt → claude → sleep → repeat
- `remote.sh` - Launcher script using your environment variables
- `.agent/STATUS.md` - Agent tracks its own progress
- `CLAUDE.md` - Development guidelines

## Architecture

```
/apps/crystalshards     - Main registry (Lucky app)
/apps/crystaldocs       - Documentation platform (Lucky app)
/apps/crystalgigs       - Job board with payments (Lucky app)
/apps/worker           - Background job processor
/infrastructure/terraform - GKE cluster setup
/infrastructure/kubernetes - K8s manifests & operators
/shared                - Shared Crystal code/models
/.github/workflows     - CI/CD pipelines
```

## In-Cluster Services

- **PostgreSQL**: CloudNativePG operator
- **Redis**: Redis operator
- **Object Storage**: MinIO
- **Autoscaling**: KEDA
- **Ingress**: NGINX with cert-manager

## Monitoring

```bash
# Watch logs
kubectl logs -f crystalshards-agent -n claude

# Check pod status
kubectl describe pod crystalshards-agent -n claude

# Get a shell
kubectl exec -it crystalshards-agent -n claude -- bash

# Check PVC usage
kubectl get pvc -n claude

# Stop the agent and cleanup
kubectl delete -f kubernetes-dev-pod.yaml
```

## Development Approach

The agent:

1. Commits after EVERY file edit
2. Self-regulates scope
3. Tracks progress in `.agent/STATUS.md`
4. Pushes to GitHub regularly
5. Creates PRs when features are complete

## Requirements

- Kubernetes cluster with kubectl configured
- GitHub token with repo permissions
- Claude API key
- envbuilder support (uses ghcr.io/coder/envbuilder:latest)
- GitHub repository configured (see GITHUB_SETUP.md)

## Cost Control

- KEDA autoscaling (scale to zero when idle)
- Apps wake on HTTP request (Heroku-style)
- In-cluster databases (no cloud SQL costs)
- MinIO for object storage (no cloud storage costs)
- Agent: 5 second sleep between iterations
- Easy to stop: `kubectl delete pod crystalshards-agent -n claude`

## GitHub Setup Required

See `GITHUB_SETUP.md` for required:

- Repository secrets
- Service account setup
- Branch protection rules
- GitHub environments
- Container registry access
