#!/bin/bash
# Grafana Deployment Verification Script
# Verifies that Grafana and all dashboards are correctly deployed

set -e

echo "=========================================="
echo "Grafana Deployment Verification"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check functions
check_passed() {
    echo -e "${GREEN}✓${NC} $1"
}

check_failed() {
    echo -e "${RED}✗${NC} $1"
}

check_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

# 1. Check if monitoring namespace exists
echo "1. Checking monitoring namespace..."
if kubectl get namespace monitoring &> /dev/null; then
    check_passed "Monitoring namespace exists"
else
    check_failed "Monitoring namespace not found"
    exit 1
fi
echo ""

# 2. Check Grafana pod
echo "2. Checking Grafana pod status..."
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$GRAFANA_POD" ]; then
    check_passed "Grafana pod found: $GRAFANA_POD"

    POD_STATUS=$(kubectl get pod -n monitoring "$GRAFANA_POD" -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        check_passed "Grafana pod is Running"
    else
        check_failed "Grafana pod is not Running (status: $POD_STATUS)"
    fi
else
    check_failed "Grafana pod not found"
    exit 1
fi
echo ""

# 3. Check Grafana service
echo "3. Checking Grafana service..."
if kubectl get svc -n monitoring prometheus-operator-grafana &> /dev/null; then
    check_passed "Grafana service exists"

    SVC_TYPE=$(kubectl get svc -n monitoring prometheus-operator-grafana -o jsonpath='{.spec.type}')
    check_passed "Service type: $SVC_TYPE"

    if [ "$SVC_TYPE" = "LoadBalancer" ]; then
        EXTERNAL_IP=$(kubectl get svc -n monitoring prometheus-operator-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        if [ -n "$EXTERNAL_IP" ]; then
            check_passed "LoadBalancer external IP: $EXTERNAL_IP"
            echo ""
            echo "    Access Grafana at: http://$EXTERNAL_IP"
            echo "    Username: admin"
            echo "    Password: admin (change this!)"
            echo ""
        else
            check_warning "LoadBalancer external IP not yet assigned (this may take a few minutes)"
        fi
    fi
else
    check_failed "Grafana service not found"
fi
echo ""

# 4. Check dashboard ConfigMaps
echo "4. Checking dashboard ConfigMaps..."
CONFIGMAPS=$(kubectl get configmaps -n monitoring -l grafana_dashboard=1 --no-headers 2>/dev/null | wc -l)
if [ "$CONFIGMAPS" -eq 5 ]; then
    check_passed "All 5 dashboard ConfigMaps found"
    kubectl get configmaps -n monitoring -l grafana_dashboard=1 --no-headers | while read -r line; do
        CM_NAME=$(echo "$line" | awk '{print $1}')
        echo "    - $CM_NAME"
    done
else
    check_failed "Expected 5 dashboard ConfigMaps, found $CONFIGMAPS"
fi
echo ""

# 5. Check PrometheusRule
echo "5. Checking PrometheusRule for alerts..."
if kubectl get prometheusrule -n monitoring crystalshards-alerts &> /dev/null; then
    check_passed "PrometheusRule 'crystalshards-alerts' exists"

    ALERT_COUNT=$(kubectl get prometheusrule -n monitoring crystalshards-alerts -o json | jq '[.spec.groups[].rules[] | select(.alert)] | length')
    check_passed "Alert rules configured: $ALERT_COUNT"
else
    check_failed "PrometheusRule 'crystalshards-alerts' not found"
fi
echo ""

# 6. Check Prometheus pod
echo "6. Checking Prometheus pod status..."
PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PROMETHEUS_POD" ]; then
    check_passed "Prometheus pod found: $PROMETHEUS_POD"

    POD_STATUS=$(kubectl get pod -n monitoring "$PROMETHEUS_POD" -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        check_passed "Prometheus pod is Running"
    else
        check_warning "Prometheus pod is not Running (status: $POD_STATUS)"
    fi
else
    check_failed "Prometheus pod not found"
fi
echo ""

# 7. Check PVC for Grafana persistence
echo "7. Checking Grafana PVC..."
GRAFANA_PVC=$(kubectl get pvc -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$GRAFANA_PVC" ]; then
    check_passed "Grafana PVC found: $GRAFANA_PVC"

    PVC_STATUS=$(kubectl get pvc -n monitoring "$GRAFANA_PVC" -o jsonpath='{.status.phase}')
    if [ "$PVC_STATUS" = "Bound" ]; then
        check_passed "PVC is Bound"

        PVC_SIZE=$(kubectl get pvc -n monitoring "$GRAFANA_PVC" -o jsonpath='{.spec.resources.requests.storage}')
        check_passed "PVC size: $PVC_SIZE"
    else
        check_warning "PVC is not Bound (status: $PVC_STATUS)"
    fi
else
    check_warning "Grafana PVC not found (persistence may be disabled)"
fi
echo ""

# 8. Check ServiceMonitors for applications
echo "8. Checking ServiceMonitors for applications..."
declare -a apps=("crystalshards" "crystaldocs" "crystalgigs" "crystalbits")
SM_COUNT=0
for app in "${apps[@]}"; do
    if kubectl get servicemonitor -n "$app" "${app}-api" &> /dev/null 2>&1; then
        check_passed "ServiceMonitor found for $app"
        SM_COUNT=$((SM_COUNT + 1))
    else
        check_warning "ServiceMonitor not found for $app (app may not be deployed yet)"
    fi
done
echo ""

# 9. Check Grafana sidecar
echo "9. Checking Grafana dashboard sidecar..."
SIDECAR_CONTAINER=$(kubectl get pod -n monitoring "$GRAFANA_POD" -o jsonpath='{.spec.containers[?(@.name=="grafana-sc-dashboard")].name}' 2>/dev/null)
if [ -n "$SIDECAR_CONTAINER" ]; then
    check_passed "Dashboard sidecar container found"

    # Check sidecar logs for errors
    SIDECAR_ERRORS=$(kubectl logs -n monitoring "$GRAFANA_POD" -c grafana-sc-dashboard --tail=50 2>/dev/null | grep -i "error" | wc -l)
    if [ "$SIDECAR_ERRORS" -eq 0 ]; then
        check_passed "No errors in sidecar logs"
    else
        check_warning "Found $SIDECAR_ERRORS errors in sidecar logs"
    fi
else
    check_failed "Dashboard sidecar container not found"
fi
echo ""

# 10. Summary
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""

# Port forwarding instructions
echo "To access Grafana via port-forward:"
echo "  kubectl port-forward -n monitoring svc/prometheus-operator-grafana 3000:80"
echo "  Then visit: http://localhost:3000"
echo ""

# Next steps
echo "Next Steps:"
echo "  1. Access Grafana UI"
echo "  2. Login with admin/admin"
echo "  3. Change the admin password"
echo "  4. Navigate to Dashboards to verify all 5 dashboards are loaded"
echo "  5. Navigate to Alerting → Alert rules to verify all 15 alerts are loaded"
echo "  6. Check Prometheus targets: kubectl port-forward -n monitoring svc/prometheus-operator-kube-prom-prometheus 9090:9090"
echo ""

# Additional checks
echo "Additional Checks (Optional):"
echo "  # View Grafana logs"
echo "  kubectl logs -n monitoring $GRAFANA_POD -c grafana"
echo ""
echo "  # View dashboard sidecar logs"
echo "  kubectl logs -n monitoring $GRAFANA_POD -c grafana-sc-dashboard"
echo ""
echo "  # List all dashboards in ConfigMaps"
echo "  kubectl get configmaps -n monitoring -l grafana_dashboard=1 -o jsonpath='{range .items[*]}{.metadata.name}{\"\\n\"}{end}'"
echo ""
echo "  # Check PrometheusRule details"
echo "  kubectl get prometheusrule -n monitoring crystalshards-alerts -o yaml"
echo ""

echo "Verification complete!"
