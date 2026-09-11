#!/bin/bash
set -euo pipefail

# AAP Instance E2E Test
# Validates AAP controller is running, route is accessible, and optional components
#
# Usage: ./e2e-test.sh [namespace]
# Example: ./e2e-test.sh ansible-automation-platform

NAMESPACE="${1:-ansible-automation-platform}"
PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }

echo "=== AAP Instance E2E Test ==="
echo "  Namespace: ${NAMESPACE}"
echo ""

# 1. Check AAP CR exists and phase
echo "--- Step 1: AAP CR status ---"
PHASE=$(oc get ansibleautomationplatform -n "${NAMESPACE}" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
if [ "${PHASE}" = "Ready" ] || [ "${PHASE}" = "Successful" ]; then
  pass "AAP CR phase: ${PHASE}"
else
  fail "AAP CR phase: ${PHASE:-not found}"
fi

# 2. Check controller pods
echo "--- Step 2: Controller pods ---"
CONTROLLER_PODS=$(oc get pods -n "${NAMESPACE}" -l app.kubernetes.io/component=automation-controller --no-headers 2>/dev/null | grep -c Running || true)
if [ "${CONTROLLER_PODS}" -ge 1 ]; then
  pass "Controller pods running: ${CONTROLLER_PODS}"
else
  fail "Controller pods running: ${CONTROLLER_PODS}"
fi

# 3. Check controller route
echo "--- Step 3: Controller route ---"
ROUTE=$(oc get route -n "${NAMESPACE}" -l app.kubernetes.io/component=automation-controller -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")
if [ -n "${ROUTE}" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -k "https://${ROUTE}/api/v2/ping/" --connect-timeout 10 || echo "000")
  if [ "${HTTP_CODE}" = "200" ]; then
    pass "Controller route accessible: https://${ROUTE} (HTTP ${HTTP_CODE})"
  else
    fail "Controller route returned HTTP ${HTTP_CODE}"
  fi
else
  fail "Controller route not found"
fi

# 4. Check EDA pods (if enabled)
echo "--- Step 4: EDA status ---"
EDA_PODS=$(oc get pods -n "${NAMESPACE}" -l app.kubernetes.io/component=eda --no-headers 2>/dev/null | grep -c Running || true)
if [ "${EDA_PODS}" -ge 1 ]; then
  pass "EDA pods running: ${EDA_PODS}"
else
  EDA_EXPECTED=$(oc get ansibleautomationplatform -n "${NAMESPACE}" -o jsonpath='{.items[0].spec.eda.disabled}' 2>/dev/null || echo "true")
  if [ "${EDA_EXPECTED}" = "true" ]; then
    pass "EDA disabled (expected)"
  else
    fail "EDA pods running: ${EDA_PODS}"
  fi
fi

# 5. Check Hub pods (if enabled)
echo "--- Step 5: Hub status ---"
HUB_PODS=$(oc get pods -n "${NAMESPACE}" -l app.kubernetes.io/component=automation-hub --no-headers 2>/dev/null | grep -c Running || true)
if [ "${HUB_PODS}" -ge 1 ]; then
  pass "Hub pods running: ${HUB_PODS}"
else
  HUB_EXPECTED=$(oc get ansibleautomationplatform -n "${NAMESPACE}" -o jsonpath='{.items[0].spec.hub.disabled}' 2>/dev/null || echo "true")
  if [ "${HUB_EXPECTED}" = "true" ]; then
    pass "Hub disabled (expected)"
  else
    fail "Hub pods running: ${HUB_PODS}"
  fi
fi

# Results
echo ""
echo "=== Results ==="
echo "  ${PASSED}/${TOTAL} passed, ${FAILED} failed"
if [ "${FAILED}" -eq 0 ]; then
  echo "  E2E TEST PASSED"
  exit 0
else
  echo "  E2E TEST FAILED"
  exit 1
fi
