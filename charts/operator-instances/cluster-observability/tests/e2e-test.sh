#!/bin/bash
set -uo pipefail

# Cluster Observability E2E Test
# Validates UIPlugin CRs on a live cluster.
#
# Usage: ./e2e-test.sh

PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

echo "=== Cluster Observability E2E Test ==="
echo ""

echo "--- Step 1: Operator installed ---"
CSV=$(oc get csv -n openshift-operators -o name 2>/dev/null | grep cluster-observability || echo "")
if [ -n "$CSV" ]; then
  PHASE=$(oc get "$CSV" -n openshift-operators -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  if [ "$PHASE" = "Succeeded" ]; then
    pass "Cluster Observability Operator CSV phase=Succeeded"
  else
    fail "Cluster Observability Operator CSV phase=$PHASE (expected Succeeded)"
  fi
else
  fail "Cluster Observability Operator CSV not found"
fi

echo "--- Step 2: UIPlugin CRD exists ---"
if oc get crd uiplugins.observability.openshift.io &>/dev/null; then
  pass "UIPlugin CRD exists"
else
  fail "UIPlugin CRD not found"
fi

echo "--- Step 3: UIPlugin resources ---"
PLUGINS=$(oc get uiplugin --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$PLUGINS" -gt 0 ]; then
  pass "$PLUGINS UIPlugin resource(s) found"
  oc get uiplugin --no-headers 2>/dev/null | while read -r line; do
    echo "    $line"
  done
else
  fail "No UIPlugin resources found"
fi

echo "--- Step 4: UIPlugin conditions ---"
ALL_AVAILABLE=true
for PLUGIN in $(oc get uiplugin -o name 2>/dev/null); do
  NAME=$(echo "$PLUGIN" | cut -d/ -f2)
  STATUS=$(oc get "$PLUGIN" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
  if [ "$STATUS" = "True" ]; then
    echo "    $NAME: Available=True"
  else
    echo "    $NAME: Available=$STATUS"
    ALL_AVAILABLE=false
  fi
done
if [ "$ALL_AVAILABLE" = true ] && [ "$PLUGINS" -gt 0 ]; then
  pass "All UIPlugins Available=True"
else
  fail "Some UIPlugins not Available"
fi

echo "--- Step 5: Console plugins enabled ---"
CONSOLE_PLUGINS=$(oc get console.operator.openshift.io cluster -o jsonpath='{.spec.plugins}' 2>/dev/null || echo "[]")
FOUND=0
for PLUGIN in $(oc get uiplugin -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  if echo "$CONSOLE_PLUGINS" | grep -q "$PLUGIN"; then
    FOUND=$((FOUND + 1))
  fi
done
if [ "$FOUND" -gt 0 ]; then
  pass "$FOUND UIPlugin(s) registered as console plugins"
else
  fail "No UIPlugins registered as console plugins (may need manual verification)"
fi

echo ""
echo "=== Results: ${PASSED}/${TOTAL} passed, ${FAILED} failed ==="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
