#!/bin/bash
set -uo pipefail

# Cluster Observability Template Test
# Validates Helm template rendering for all UIPlugin combinations.
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

echo "=== Cluster Observability Template Tests ==="
echo ""

# --- All disabled by default ---
echo "--- Default values (all disabled) ---"
OUTPUT=$(helm template test "$CHART_DIR" 2>&1)
if echo "$OUTPUT" | grep -q "kind: UIPlugin"; then
  fail "Default values should render no UIPlugin resources"
else
  pass "Default values render no UIPlugin resources"
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

# --- Logging UIPlugin ---
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

# --- Logging with custom LokiStack ---
echo "--- Logging with custom LokiStack ---"
OUTPUT=$(render "uiPlugins.logging.include=true,uiPlugins.logging.lokiStack.name=my-loki")
if echo "$OUTPUT" | grep -q "name: my-loki"; then
  pass "Logging uses custom LokiStack name"
else
  fail "Logging ignores custom LokiStack name"
fi

# --- Monitoring UIPlugin ---
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
  fail "Monitoring should not render spec.monitoring when acm is disabled"
else
  pass "Monitoring omits spec.monitoring when acm is disabled"
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

# --- All enabled ---
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
  pass "Correct API version used"
else
  fail "Wrong API version"
fi

# --- Selective enable (only dashboards + logging) ---
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

echo ""
echo "=== Results: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
exit $FAILED
