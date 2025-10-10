#!/bin/bash
# Agent RBAC Verification Script
# Tests that the agent service account has correct read-only permissions

set -e

KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-gke_crystalshards-org_us-central1_crystalshards-cluster}"
SERVICE_ACCOUNT="system:serviceaccount:claude:claude-agent"

echo "=========================================="
echo "Agent RBAC Verification"
echo "=========================================="
echo "Context: $KUBECTL_CONTEXT"
echo "Service Account: $SERVICE_ACCOUNT"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_passed() {
    echo -e "${GREEN}✓${NC} $1"
}

check_failed() {
    echo -e "${RED}✗${NC} $1"
}

check_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

# 1. Verify namespace exists
echo "1. Checking claude namespace..."
if kubectl --context "$KUBECTL_CONTEXT" get namespace claude &> /dev/null; then
    check_passed "Namespace 'claude' exists"
else
    check_failed "Namespace 'claude' not found - run terraform apply first"
    exit 1
fi
echo ""

# 2. Verify service account exists
echo "2. Checking service account..."
if kubectl --context "$KUBECTL_CONTEXT" get serviceaccount claude-agent -n claude &> /dev/null; then
    check_passed "ServiceAccount 'claude-agent' exists"
else
    check_failed "ServiceAccount not found - run terraform apply first"
    exit 1
fi
echo ""

# 3. Verify ClusterRole exists
echo "3. Checking ClusterRole..."
if kubectl --context "$KUBECTL_CONTEXT" get clusterrole claude-agent-role &> /dev/null; then
    check_passed "ClusterRole 'claude-agent-role' exists"

    # Count rules
    RULE_COUNT=$(kubectl --context "$KUBECTL_CONTEXT" get clusterrole claude-agent-role -o json | jq '.rules | length')
    check_passed "ClusterRole has $RULE_COUNT permission rules"
else
    check_failed "ClusterRole not found - run terraform apply first"
    exit 1
fi
echo ""

# 4. Verify ClusterRoleBinding exists
echo "4. Checking ClusterRoleBinding..."
if kubectl --context "$KUBECTL_CONTEXT" get clusterrolebinding claude-agent-binding &> /dev/null; then
    check_passed "ClusterRoleBinding 'claude-agent-binding' exists"

    # Verify binding
    BOUND_SA=$(kubectl --context "$KUBECTL_CONTEXT" get clusterrolebinding claude-agent-binding -o jsonpath='{.subjects[0].name}')
    if [ "$BOUND_SA" = "claude-agent" ]; then
        check_passed "ClusterRoleBinding correctly bound to service account"
    else
        check_failed "ClusterRoleBinding not correctly bound (found: $BOUND_SA)"
    fi
else
    check_failed "ClusterRoleBinding not found - run terraform apply first"
    exit 1
fi
echo ""

# 5. Test read permissions (should succeed)
echo "5. Testing READ permissions (should succeed)..."

declare -a read_tests=(
    "list:pods::pods"
    "list:services::services"
    "list:deployments:apps:deployments"
    "get:configmaps::configmaps"
    "get:secrets::secrets"
    "list:nodes::nodes"
    "get:clusters:postgresql.cnpg.io:clusters"
    "list:redis:redis.redis.opstreelabs.in:redis"
    "get:servicemonitors:monitoring.coreos.com:servicemonitors"
)

PASSED=0
FAILED=0

for test in "${read_tests[@]}"; do
    IFS=':' read -r verb resource apigroup resource_name <<< "$test"

    if [ -z "$apigroup" ]; then
        RESULT=$(kubectl --context "$KUBECTL_CONTEXT" auth can-i "$verb" "$resource" --as="$SERVICE_ACCOUNT" 2>&1)
    else
        RESULT=$(kubectl --context "$KUBECTL_CONTEXT" auth can-i "$verb" "$resource" --as="$SERVICE_ACCOUNT" --api-group="$apigroup" 2>&1)
    fi

    if [ "$RESULT" = "yes" ]; then
        check_passed "Can $verb $resource_name"
        ((PASSED++))
    else
        check_failed "Cannot $verb $resource_name (expected: yes, got: $RESULT)"
        ((FAILED++))
    fi
done

echo ""
echo "Read permission tests: $PASSED passed, $FAILED failed"
echo ""

# 6. Test write restrictions (should fail)
echo "6. Testing WRITE restrictions (should fail)..."

declare -a write_tests=(
    "create:pods::pods"
    "delete:pods::pods"
    "update:configmaps::configmaps"
    "patch:deployments:apps:deployments"
    "create:secrets::secrets"
    "delete:services::services"
)

PASSED=0
FAILED=0

for test in "${write_tests[@]}"; do
    IFS=':' read -r verb resource apigroup resource_name <<< "$test"

    if [ -z "$apigroup" ]; then
        RESULT=$(kubectl --context "$KUBECTL_CONTEXT" auth can-i "$verb" "$resource" --as="$SERVICE_ACCOUNT" 2>&1)
    else
        RESULT=$(kubectl --context "$KUBECTL_CONTEXT" auth can-i "$verb" "$resource" --as="$SERVICE_ACCOUNT" --api-group="$apigroup" 2>&1)
    fi

    if [ "$RESULT" = "no" ]; then
        check_passed "Cannot $verb $resource_name (correctly restricted)"
        ((PASSED++))
    else
        check_failed "CAN $verb $resource_name (should be restricted!)"
        ((FAILED++))
    fi
done

echo ""
echo "Write restriction tests: $PASSED passed, $FAILED failed"
echo ""

# 7. Test operator CRD access
echo "7. Testing Operator CRD access..."

declare -a operator_tests=(
    "get:clusters:postgresql.cnpg.io:CNPG PostgreSQL clusters"
    "list:backups:postgresql.cnpg.io:CNPG backups"
    "get:redis:redis.redis.opstreelabs.in:Redis instances"
    "list:tenants:minio.min.io:MinIO tenants"
    "get:certificates:cert-manager.io:Cert-Manager certificates"
)

for test in "${operator_tests[@]}"; do
    IFS=':' read -r verb resource apigroup display_name <<< "$test"

    RESULT=$(kubectl --context "$KUBECTL_CONTEXT" auth can-i "$verb" "$resource" --as="$SERVICE_ACCOUNT" --api-group="$apigroup" 2>&1)

    if [ "$RESULT" = "yes" ]; then
        check_passed "Can access $display_name"
    else
        check_warning "Cannot access $display_name (CRD may not be installed)"
    fi
done

echo ""

# 8. Summary
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All RBAC permissions are correctly configured${NC}"
    echo ""
    echo "The agent has:"
    echo "  - Read-only access to all necessary resources"
    echo "  - NO write permissions (correctly restricted)"
    echo "  - Access to operator CRDs for debugging"
    echo ""
    echo "Next steps:"
    echo "  1. Deploy or restart agent pod to use new permissions"
    echo "  2. Test from within pod: kubectl get pods --all-namespaces"
    echo "  3. Verify logs access: kubectl logs -n <namespace> <pod>"
else
    echo -e "${RED}✗ Some RBAC tests failed${NC}"
    echo ""
    echo "Please check:"
    echo "  1. Terraform has been applied: cd terraform && terraform apply"
    echo "  2. ClusterRole and ClusterRoleBinding exist"
    echo "  3. Service account is correctly bound"
fi

echo ""
echo "To test from agent pod:"
echo "  kubectl --context $KUBECTL_CONTEXT exec -it claude-agent -n claude -c agent -- bash"
echo "  Then run: kubectl get pods --all-namespaces"
echo ""
echo "Verification complete!"
