#!/bin/bash
set -euo pipefail

# This script diagnoses application deployment issues
# It requires kubectl access to all namespaces

echo "========================================="
echo "CrystalShards Deployment Diagnostics"
echo "========================================="
echo ""

APPS=("crystalshards" "crystaldocs" "crystalgigs" "crystalbits")

for app in "${APPS[@]}"; do
  echo "--- Checking $app ---"

  # Check namespace exists
  if ! kubectl get namespace "$app" &>/dev/null; then
    echo "❌ Namespace '$app' does not exist!"
    echo ""
    continue
  fi

  echo "✓ Namespace exists"

  # Check deployments
  echo ""
  echo "Deployments:"
  kubectl get deployments -n "$app" -o wide 2>&1 || echo "  ❌ Cannot access deployments"

  # Check pods
  echo ""
  echo "Pods:"
  kubectl get pods -n "$app" -o wide 2>&1 || echo "  ❌ Cannot access pods"

  # Check pod events
  echo ""
  echo "Recent Events:"
  kubectl get events -n "$app" --sort-by='.lastTimestamp' | tail -10 2>&1 || echo "  ❌ Cannot access events"

  # Check secrets existence
  echo ""
  echo "Secrets:"
  kubectl get secrets -n "$app" 2>&1 || echo "  ❌ Cannot access secrets"

  # Check if PostgreSQL cluster exists
  echo ""
  echo "PostgreSQL Cluster:"
  kubectl get cluster.postgresql.cnpg.io -n "$app" 2>&1 || echo "  ⚠️  No PostgreSQL clusters found or cannot access"

  # Check services
  echo ""
  echo "Services:"
  kubectl get services -n "$app" 2>&1 || echo "  ❌ Cannot access services"

  echo ""
  echo "========================================="
  echo ""
done

# Check infrastructure dependencies
echo "--- Infrastructure Dependencies ---"
echo ""
echo "Shared Redis:"
kubectl get redis -n infrastructure 2>&1 || echo "  ⚠️  Cannot check Redis status"

echo ""
echo "Shared MinIO:"
kubectl get tenants.minio.min.io -n infrastructure 2>&1 || echo "  ⚠️  Cannot check MinIO status"

echo ""
echo "MinIO User Secrets:"
kubectl get secret -n infrastructure | grep storage-user 2>&1 || echo "  ⚠️  Cannot check MinIO secrets"

echo ""
echo "========================================="

# Detailed pod inspection for each app
echo ""
echo "--- Detailed Pod Inspection ---"
for app in "${APPS[@]}"; do
  echo ""
  echo "Checking pods in $app namespace:"

  # Get pod names
  pods=$(kubectl get pods -n "$app" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

  if [ -z "$pods" ]; then
    echo "  No pods found or cannot access"
    continue
  fi

  for pod in $pods; do
    echo ""
    echo "  Pod: $pod"

    # Get pod status
    status=$(kubectl get pod "$pod" -n "$app" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    echo "    Status: $status"

    # Get container statuses
    echo "    Container Status:"
    kubectl get pod "$pod" -n "$app" -o jsonpath='{range .status.containerStatuses[*]}{"      - "}{.name}{": "}{.ready}{" (ready: "}{.started}{")"}{"\n"}{end}' 2>/dev/null || echo "      Cannot access"

    # Check for common issues
    echo "    Waiting Reason:"
    kubectl get pod "$pod" -n "$app" -o jsonpath='{range .status.containerStatuses[*]}{"      - "}{.name}{": "}{.state.waiting.reason}{" - "}{.state.waiting.message}{"\n"}{end}' 2>/dev/null || echo "      Not waiting"

    # Get recent logs (if pod is running)
    if [ "$status" = "Running" ] || [ "$status" = "CrashLoopBackOff" ]; then
      echo "    Recent Logs (last 20 lines):"
      kubectl logs "$pod" -n "$app" --tail=20 2>&1 | sed 's/^/      /' || echo "      Cannot access logs"
    fi

    # Describe pod for full details
    echo "    Full Pod Description:"
    kubectl describe pod "$pod" -n "$app" 2>&1 | tail -50 | sed 's/^/      /' || echo "      Cannot describe pod"
  done
done

echo ""
echo "========================================="
echo "Diagnostics Complete"
echo "========================================="
