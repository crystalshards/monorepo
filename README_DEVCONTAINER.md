# CrystalShards DevContainer Setup

This project is configured to run autonomously in a Kubernetes environment using envbuilder.

## Quick Start

### Local Development (VS Code)

1. Install Docker and VS Code with the Dev Containers extension
2. Open this folder in VS Code
3. Click "Reopen in Container" when prompted
4. The development environment will be set up automatically

### Kubernetes Deployment with envbuilder

1. Create the required secrets:

```bash
# Claude API key
kubectl create secret generic claude-secrets \
  --from-literal=api-key="your-claude-api-key"

# GitHub token (needs repo, workflow, and packages permissions)
kubectl create secret generic github-secrets \
  --from-literal=token="your-github-token"
```

2. Deploy the development pod:

```bash
kubectl apply -f kubernetes-dev-pod.yaml
```

3. The pod will

   - Clone this repository
   - Build the devcontainer environment
   - Start the autonomous development loop

4. Monitor the progress:

```bash
kubectl logs -f crystalshards-dev
```

5. Access the running container:

```bash
kubectl exec -it crystalshards-dev -- /bin/bash
```

## Manual Launch with kubectl run

For quick testing:

```bash
kubectl run crystalshards-dev \
  --image=ghcr.io/coder/envbuilder:latest \
  --restart=Always \
  --env="ENVBUILDER_GIT_URL=https://github.com/crystalshards/crystalshards-claude.git" \
  --env="ENVBUILDER_DEVCONTAINER_DIR=/workspaces/monorepo/.devcontainer" \
  --env="ENVBUILDER_INIT_SCRIPT=/workspaces/monorepo/develop.sh" \
  --env="CLAUDE_CODE_OAUTH_TOKEN=your-api-key" \
  --env="GITHUB_TOKEN=your-github-token" \
  --env="GIT_AUTHOR_NAME=CrystalShards Bot" \
  --env="GIT_AUTHOR_EMAIL=bot@crystalshards.org"
```

## Automated Launch Script

Use the `remote.sh` script for easier deployment:

```bash
# Export required environment variables
export CLAUDE_CODE_OAUTH_TOKEN="your-claude-api-key"
export GITHUB_TOKEN="your-github-token"

# Run the launcher script
./remote.sh
```

The script will:

- Check for required environment variables
- Create a pod with restart=Always policy
- Configure envbuilder to run develop.sh automatically
- Optionally tail the logs

## What Happens

1. envbuilder clones the repository
2. Builds the devcontainer environment based on `.devcontainer/devcontainer.json`
3. Runs `develop.sh` which starts the autonomous loop
4. Claude reads `PROMPT.md` and executes one task per iteration
5. Updates `PROMPT.md` with progress after each task
6. Continues until all tasks are complete

## Files

- `.devcontainer/devcontainer.json` - Dev container configuration
- `.devcontainer/Dockerfile` - Container image definition
- `.devcontainer/onCreateCommand.sh` - Initial setup script
- `.devcontainer/postStartCommand.sh` - Service startup script
- `develop.sh` - Main autonomous loop script
- `PROMPT.md` - Task queue and state tracking
- `CLAUDE.md` - Development guidelines

## Environment

The container includes:

- Crystal language (latest)
- Lucky framework CLI
- PostgreSQL client
- Redis tools
- Docker-in-Docker
- Kubectl and Terraform
- GitHub CLI

## GitHub Token Requirements

The GitHub token needs the following permissions:

- **repo**: Full control of private repositories
- **workflow**: Update GitHub Action workflows
- **write:packages**: Upload packages to GitHub Package Registry
- **admin:org**: Manage organization (if creating repos under org)

Create a token at: <https://github.com/settings/tokens/new>

## Git Workflow

The bot will:

1. Configure git with bot identity
2. Create feature branches for each task
3. Commit changes frequently (every 30 minutes)
4. Push to remote after 2-3 commits
5. Create pull requests when features are complete

Commits follow the format: `type(scope): description`

- Types: feat, fix, docs, style, refactor, test, chore

## Troubleshooting

If the pod fails to start:

```bash
kubectl describe pod crystalshards-dev
kubectl logs crystalshards-dev
```

To restart:

```bash
kubectl delete pod crystalshards-dev
kubectl apply -f kubernetes-dev-pod.yaml
```
