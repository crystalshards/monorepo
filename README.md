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
3. **CrystalGigs.com** - Job board for Crystal developers
4. **CrystalBits.org** - Newsletter/blog platform

Features:

- Full-text search, dependency graphs, download stats
- Automated documentation generation with background workers
- Everything runs in-cluster (no external cloud services)
- Security-hardened with non-root containers and minimal capabilities
- GKE Autopilot for automatic scaling and optimization

## Files

- `PROMPT.md` - Simple prompt that guides the agent
- `develop.sh` - Continuous loop: prompt → claude → sleep → repeat
- `remote.sh` - Launcher script using your environment variables
- `.agent/STATUS.md` - Agent tracks its own progress
- `CLAUDE.md` - Development guidelines

## Architecture

```
/apps/crystalshards     - Main registry (Lucky app + Mosquito workers)
/apps/crystaldocs       - Documentation platform (Lucky app)
/apps/crystalgigs       - Job board (Lucky app)
/apps/crystalbits       - Newsletter/blog (Lucky app)
/terraform              - Infrastructure as Code (GKE, K8s resources)
  /modules/networking   - VPC, subnets, Cloud NAT
  /modules/cluster      - GKE Autopilot cluster
  /modules/operators    - Infrastructure operators
  /modules/ingress      - Traefik + external-dns
  /modules/applications - App-specific K8s resources
/.github/workflows      - CI/CD pipelines
```

## In-Cluster Services

- **PostgreSQL**: CloudNativePG operator (per-app databases)
- **Redis**: Redis operator (shared cluster)
- **Object Storage**: MinIO operator (packages & docs)
- **Background Jobs**: Mosquito (Crystal job framework)
- **Ingress**: Traefik with cert-manager
- **Monitoring**: Prometheus + Grafana

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

- GKE Autopilot (pay only for running pods, automatic bin-packing)
- In-cluster databases with CNPG (no Cloud SQL costs)
- MinIO for object storage (no Cloud Storage costs)
- Traefik ingress (no external load balancer costs per app)
- Resource limits on all pods for predictable costs
- Estimated monthly cost: $185-310

## GitHub Setup Required

See `GITHUB_SETUP.md` for required:

- Repository secrets
- Service account setup
- Branch protection rules
- GitHub environments
- Container registry access
