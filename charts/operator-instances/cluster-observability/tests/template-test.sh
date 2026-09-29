#!/bin/bash
set -uo pipefail

# Cluster Observability Template Test
# Validates Helm template rendering for all UIPlugin, MonitoringStack,
# and ThanosQuerier combinations.
#
# Usage: ./template-test.sh

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); TOTAL=$((TOTAL + 1)); }

render() {
  helm template test "$CHART_DIR" --set "$1" 2>&1
}

render_values() {
  helm template test "$CHART_DIR" -f "$1" 2>&1
}

echo "=== Cluster Observability Template Tests ==="
echo ""

# ==========================================================================
# UIPlugin tests
# ==========================================================================

# --- All disabled by default ---
echo "--- Default values (all disabled) ---"
OUTPUT=$(helm template test "$CHART_DIR" 2>&1)
if echo "$OUTPUT" | grep -q "kind: UIPlugin"; then
  fail "Default values should render no UIPlugin resources"
else
  pass "Default values render no UIPlugin resources"
fi
if echo "$OUTPUT" | grep -q "kind: MonitoringStack"; then
  fail "Default values should render no MonitoringStack resources"
else
  pass "Default values render no MonitoringStack resources"
fi
if echo "$OUTPUT" | grep -q "kind: ThanosQuerier"; then
  fail "Default values should render no ThanosQuerier resources"
else
  pass "Default values render no ThanosQuerier resources"
fi

# --- Dashboards UIPlugin ---
echo "--- Dashboards UIPlugin ---"
OUTPUT=$(render "uiPlugins.dashboards.include=true")
if echo "$OUTPUT" | grep -q "name: dashboards"; then
  pass "Dashboards UIPlugin rendered"
else
  fail "Dashboards UIPlugin not rendered"
fi
if echo "$OUTPUT" | grep -q "type: Dashboards"; then
  pass "Dashboards UIPlugin has correct type"
else
  fail "Dashboards UIPlugin has incorrect type"
fi

# --- Troubleshooting Panel UIPlugin ---
echo "--- Troubleshooting Panel UIPlugin ---"
OUTPUT=$(render "uiPlugins.troubleshootingPanel.include=true")
if echo "$OUTPUT" | grep -q "name: troubleshooting-panel"; then
  pass "TroubleshootingPanel UIPlugin rendered"
else
  fail "TroubleshootingPanel UIPlugin not rendered"
fi
if echo "$OUTPUT" | grep -q "type: TroubleshootingPanel"; then
  pass "TroubleshootingPanel UIPlugin has correct type"
else
  fail "TroubleshootingPanel UIPlugin has incorrect type"
fi

# --- Distributed Tracing UIPlugin ---
echo "--- Distributed Tracing UIPlugin ---"
OUTPUT=$(render "uiPlugins.distributedTracing.include=true")
if echo "$OUTPUT" | grep -q "name: distributed-tracing"; then
  pass "DistributedTracing UIPlugin rendered"
else
  fail "DistributedTracing UIPlugin not rendered"
fi
if echo "$OUTPUT" | grep -q "type: DistributedTracing"; then
  pass "DistributedTracing UIPlugin has correct type"
else
  fail "DistributedTracing UIPlugin has incorrect type"
fi
if echo "$OUTPUT" | grep -q "distributedTracing:"; then
  fail "DistributedTracing should not render spec.distributedTracing when timeout is empty"
else
  pass "DistributedTracing omits spec.distributedTracing when timeout is empty"
fi

# --- Distributed Tracing with timeout ---
echo "--- Distributed Tracing with timeout ---"
OUTPUT=$(render "uiPlugins.distributedTracing.include=true,uiPlugins.distributedTracing.timeout=30s")
if echo "$OUTPUT" | grep -q "timeout: 30s"; then
  pass "DistributedTracing renders custom timeout"
else
  fail "DistributedTracing missing custom timeout"
fi

# --- Logging UIPlugin (basic) ---
echo "--- Logging UIPlugin ---"
OUTPUT=$(render "uiPlugins.logging.include=true")
if echo "$OUTPUT" | grep -q "name: logging"; then
  pass "Logging UIPlugin rendered"
else
  fail "Logging UIPlugin not rendered"
fi
if echo "$OUTPUT" | grep -q "type: Logging"; then
  pass "Logging UIPlugin has correct type"
else
  fail "Logging UIPlugin has incorrect type"
fi
if echo "$OUTPUT" | grep -q "name: logging-lokistack"; then
  pass "Logging references default LokiStack name"
else
  fail "Logging missing default LokiStack name"
fi
if echo "$OUTPUT" | grep -q "logsLimit:"; then
  fail "Logging should omit logsLimit when 0"
else
  pass "Logging omits logsLimit when default (0)"
fi
if echo "$OUTPUT" | grep -q "schema:"; then
  fail "Logging should omit schema when empty"
else
  pass "Logging omits schema when empty"
fi

# --- Logging with all optional fields ---
echo "--- Logging with optional fields ---"
OUTPUT=$(render "uiPlugins.logging.include=true,uiPlugins.logging.lokiStack.name=my-loki,uiPlugins.logging.logsLimit=100,uiPlugins.logging.timeout=30s,uiPlugins.logging.schema=otel")
if echo "$OUTPUT" | grep -q "name: my-loki"; then
  pass "Logging uses custom LokiStack name"
else
  fail "Logging ignores custom LokiStack name"
fi
if echo "$OUTPUT" | grep -q "logsLimit: 100"; then
  pass "Logging renders logsLimit"
else
  fail "Logging missing logsLimit"
fi
if echo "$OUTPUT" | grep -q "timeout: 30s"; then
  pass "Logging renders timeout"
else
  fail "Logging missing timeout"
fi
if echo "$OUTPUT" | grep -q "schema: otel"; then
  pass "Logging renders schema"
else
  fail "Logging missing schema"
fi

# --- Monitoring UIPlugin (basic) ---
echo "--- Monitoring UIPlugin ---"
OUTPUT=$(render "uiPlugins.monitoring.include=true")
if echo "$OUTPUT" | grep -q "name: monitoring"; then
  pass "Monitoring UIPlugin rendered"
else
  fail "Monitoring UIPlugin not rendered"
fi
if echo "$OUTPUT" | grep -q "type: Monitoring"; then
  pass "Monitoring UIPlugin has correct type"
else
  fail "Monitoring UIPlugin has incorrect type"
fi
if echo "$OUTPUT" | grep -q "monitoring:"; then
  fail "Monitoring should not render spec.monitoring when all sub-features are disabled"
else
  pass "Monitoring omits spec.monitoring when all sub-features are disabled"
fi

# --- Monitoring with ACM ---
echo "--- Monitoring with ACM ---"
OUTPUT=$(render "uiPlugins.monitoring.include=true,uiPlugins.monitoring.acm.enabled=true,uiPlugins.monitoring.acm.alertmanager.url=https://alertmanager.example.com,uiPlugins.monitoring.acm.thanosQuerier.url=https://thanos.example.com")
if echo "$OUTPUT" | grep -q "enabled: true"; then
  pass "Monitoring renders ACM enabled"
else
  fail "Monitoring missing ACM enabled"
fi
if echo "$OUTPUT" | grep -q "https://alertmanager.example.com"; then
  pass "Monitoring renders alertmanager URL"
else
  fail "Monitoring missing alertmanager URL"
fi
if echo "$OUTPUT" | grep -q "https://thanos.example.com"; then
  pass "Monitoring renders thanosQuerier URL"
else
  fail "Monitoring missing thanosQuerier URL"
fi

# --- Monitoring with clusterHealthAnalyzer ---
echo "--- Monitoring with clusterHealthAnalyzer ---"
OUTPUT=$(render "uiPlugins.monitoring.include=true,uiPlugins.monitoring.clusterHealthAnalyzer.enabled=true")
if echo "$OUTPUT" | grep -q "clusterHealthAnalyzer:"; then
  pass "Monitoring renders clusterHealthAnalyzer section"
else
  fail "Monitoring missing clusterHealthAnalyzer section"
fi

# --- Monitoring with Perses ---
echo "--- Monitoring with Perses ---"
OUTPUT=$(render "uiPlugins.monitoring.include=true,uiPlugins.monitoring.perses.enabled=true")
if echo "$OUTPUT" | grep -q "perses:"; then
  pass "Monitoring renders perses section"
else
  fail "Monitoring missing perses section"
fi

# --- All UIPlugins enabled ---
echo "--- All UIPlugins enabled ---"
OUTPUT=$(render "uiPlugins.dashboards.include=true,uiPlugins.troubleshootingPanel.include=true,uiPlugins.distributedTracing.include=true,uiPlugins.logging.include=true,uiPlugins.monitoring.include=true")
COUNT=$(echo "$OUTPUT" | grep -c "kind: UIPlugin")
if [ "$COUNT" -eq 5 ]; then
  pass "All 5 UIPlugins rendered when all enabled"
else
  fail "Expected 5 UIPlugins, got $COUNT"
fi

# --- API version ---
echo "--- API version ---"
OUTPUT=$(render "uiPlugins.dashboards.include=true")
if echo "$OUTPUT" | grep -q "observability.openshift.io/v1alpha1"; then
  pass "Correct UIPlugin API version used"
else
  fail "Wrong UIPlugin API version"
fi

# --- Selective enable ---
echo "--- Selective enable ---"
OUTPUT=$(render "uiPlugins.dashboards.include=true,uiPlugins.logging.include=true")
COUNT=$(echo "$OUTPUT" | grep -c "kind: UIPlugin")
if [ "$COUNT" -eq 2 ]; then
  pass "Exactly 2 UIPlugins rendered for selective enable"
else
  fail "Expected 2 UIPlugins, got $COUNT"
fi
if echo "$OUTPUT" | grep -q "name: troubleshooting-panel"; then
  fail "TroubleshootingPanel should not render when disabled"
else
  pass "TroubleshootingPanel correctly excluded when disabled"
fi
if echo "$OUTPUT" | grep -q "name: distributed-tracing"; then
  fail "DistributedTracing should not render when disabled"
else
  pass "DistributedTracing correctly excluded when disabled"
fi
if echo "$OUTPUT" | grep -q "name: monitoring"; then
  fail "Monitoring should not render when disabled"
else
  pass "Monitoring correctly excluded when disabled"
fi

# ==========================================================================
# MonitoringStack tests
# ==========================================================================

echo ""
echo "--- MonitoringStack ---"

# Create a temp values file for list-based resources
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/ms-basic.yaml" <<'YAML'
monitoringStacks:
  - include: true
    name: team-alpha
    namespace: team-alpha-monitoring
    namespaceSelector:
      matchLabels:
        team: alpha
    resourceSelector:
      matchLabels:
        monitoring: enabled
    resources:
      requests:
        cpu: 500m
        memory: 512Mi
YAML

OUTPUT=$(render_values "$TMPDIR/ms-basic.yaml")
if echo "$OUTPUT" | grep -q "kind: MonitoringStack"; then
  pass "MonitoringStack rendered"
else
  fail "MonitoringStack not rendered"
fi
if echo "$OUTPUT" | grep -q "monitoring.rhobs/v1alpha1"; then
  pass "MonitoringStack uses correct API version"
else
  fail "MonitoringStack uses wrong API version"
fi
if echo "$OUTPUT" | grep -q "name: team-alpha"; then
  pass "MonitoringStack has correct name"
else
  fail "MonitoringStack has incorrect name"
fi
if echo "$OUTPUT" | grep -q "namespace: team-alpha-monitoring"; then
  pass "MonitoringStack has correct namespace"
else
  fail "MonitoringStack has incorrect namespace"
fi
if echo "$OUTPUT" | grep -q "team: alpha"; then
  pass "MonitoringStack renders namespaceSelector"
else
  fail "MonitoringStack missing namespaceSelector"
fi
if echo "$OUTPUT" | grep -q "monitoring: enabled"; then
  pass "MonitoringStack renders resourceSelector"
else
  fail "MonitoringStack missing resourceSelector"
fi
if echo "$OUTPUT" | grep -q "cpu: 500m"; then
  pass "MonitoringStack renders resources"
else
  fail "MonitoringStack missing resources"
fi

# --- MonitoringStack with prometheusConfig ---
echo "--- MonitoringStack with prometheusConfig ---"
cat > "$TMPDIR/ms-prometheus.yaml" <<'YAML'
monitoringStacks:
  - include: true
    name: full-stack
    namespace: monitoring
    prometheusConfig:
      retention: 48h
      replicas: 2
      persistentVolumeClaim:
        storageClassName: YOUR_STORAGE_CLASS
        resources:
          requests:
            storage: 100Gi
      remoteWrite:
        - url: https://remote.example.com/api/v1/write
YAML

OUTPUT=$(render_values "$TMPDIR/ms-prometheus.yaml")
if echo "$OUTPUT" | grep -q "retention: 48h"; then
  pass "MonitoringStack renders prometheusConfig.retention"
else
  fail "MonitoringStack missing prometheusConfig.retention"
fi
if echo "$OUTPUT" | grep -q "storageClassName: YOUR_STORAGE_CLASS"; then
  pass "MonitoringStack renders PVC storageClassName"
else
  fail "MonitoringStack missing PVC storageClassName"
fi
if echo "$OUTPUT" | grep -q "https://remote.example.com"; then
  pass "MonitoringStack renders remoteWrite URL"
else
  fail "MonitoringStack missing remoteWrite URL"
fi

# --- MonitoringStack disabled ---
echo "--- MonitoringStack disabled ---"
cat > "$TMPDIR/ms-disabled.yaml" <<'YAML'
monitoringStacks:
  - include: false
    name: disabled-stack
    namespace: monitoring
YAML

OUTPUT=$(render_values "$TMPDIR/ms-disabled.yaml")
if echo "$OUTPUT" | grep -q "kind: MonitoringStack"; then
  fail "Disabled MonitoringStack should not render"
else
  pass "Disabled MonitoringStack correctly excluded"
fi

# --- Multiple MonitoringStacks ---
echo "--- Multiple MonitoringStacks ---"
cat > "$TMPDIR/ms-multi.yaml" <<'YAML'
monitoringStacks:
  - include: true
    name: stack-a
    namespace: ns-a
  - include: true
    name: stack-b
    namespace: ns-b
  - include: false
    name: stack-c
    namespace: ns-c
YAML

OUTPUT=$(render_values "$TMPDIR/ms-multi.yaml")
COUNT=$(echo "$OUTPUT" | grep -c "kind: MonitoringStack")
if [ "$COUNT" -eq 2 ]; then
  pass "2 of 3 MonitoringStacks rendered (1 disabled)"
else
  fail "Expected 2 MonitoringStacks, got $COUNT"
fi

# ==========================================================================
# ThanosQuerier tests
# ==========================================================================

echo ""
echo "--- ThanosQuerier ---"

cat > "$TMPDIR/tq-basic.yaml" <<'YAML'
thanosQueriers:
  - include: true
    name: federated-query
    namespace: observability
    selector:
      matchLabels:
        stack-type: federated
    namespaceSelector:
      matchLabels:
        observability: enabled
YAML

OUTPUT=$(render_values "$TMPDIR/tq-basic.yaml")
if echo "$OUTPUT" | grep -q "kind: ThanosQuerier"; then
  pass "ThanosQuerier rendered"
else
  fail "ThanosQuerier not rendered"
fi
if echo "$OUTPUT" | grep -q "monitoring.rhobs/v1alpha1"; then
  pass "ThanosQuerier uses correct API version"
else
  fail "ThanosQuerier uses wrong API version"
fi
if echo "$OUTPUT" | grep -q "name: federated-query"; then
  pass "ThanosQuerier has correct name"
else
  fail "ThanosQuerier has incorrect name"
fi
if echo "$OUTPUT" | grep -q "stack-type: federated"; then
  pass "ThanosQuerier renders selector"
else
  fail "ThanosQuerier missing selector"
fi
if echo "$OUTPUT" | grep -q "observability: enabled"; then
  pass "ThanosQuerier renders namespaceSelector"
else
  fail "ThanosQuerier missing namespaceSelector"
fi

# --- ThanosQuerier disabled ---
echo "--- ThanosQuerier disabled ---"
cat > "$TMPDIR/tq-disabled.yaml" <<'YAML'
thanosQueriers:
  - include: false
    name: disabled
    namespace: observability
YAML

OUTPUT=$(render_values "$TMPDIR/tq-disabled.yaml")
if echo "$OUTPUT" | grep -q "kind: ThanosQuerier"; then
  fail "Disabled ThanosQuerier should not render"
else
  pass "Disabled ThanosQuerier correctly excluded"
fi

echo ""
echo "=== Results: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
exit $FAILED
