#!/bin/bash
set -euo pipefail

# This script applies RBAC permissions for the Claude agent
# Must be run by someone with cluster-admin access

echo "Applying agent RBAC configuration..."

kubectl apply -f /workspaces/monorepo/kubernetes-agent-rbac.yaml

echo "RBAC configuration applied successfully!"
echo ""
echo "Verifying permissions..."
kubectl auth can-i list pods --all-namespaces --as=system:serviceaccount:claude:default

echo ""
echo "Agent now has permissions to inspect cluster resources."
