#!/bin/bash
set -euo pipefail

# ACS Central E2E Test
# Validates Central deployment, route, API, init-bundle, and scanner.
#
# Usage: ./e2e-test.sh [namespace]
# Default namespace: stackrox

NS="${1:-stackrox}"
PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }

echo "=== ACS Central E2E Test ==="
echo "  Namespace: ${NS}"
echo ""

echo "--- Step 1: Central CR status ---"
DEPLOYED=$(oc get central stackrox-central-services -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="Deployed")].status}' 2>/dev/null || echo "NotFound")
if [ "$DEPLOYED" = "True" ]; then
  pass "Central CR Deployed=True"
else
  fail "Central CR Deployed=$DEPLOYED (expected True)"
fi

echo "--- Step 2: Central pods ---"
NOT_READY=$(oc get pods -n "$NS" -l app=central --no-headers 2>/dev/null | grep -cv "Running" || true)
TOTAL_PODS=$(oc get pods -n "$NS" -l app=central --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$TOTAL_PODS" -gt 0 ] && [ "$NOT_READY" -eq 0 ]; then
  pass "All ${TOTAL_PODS} Central pods running"
else
  fail "${NOT_READY} of ${TOTAL_PODS} Central pods not running"
fi

echo "--- Step 3: Central route and API ---"
ROUTE=$(oc get route central -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$ROUTE" ]; then
  HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "https://${ROUTE}/v1/ping" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" -eq 200 ]; then
    pass "Central API https://${ROUTE}/v1/ping returned 200"
  else
    fail "Central API returned HTTP ${HTTP_CODE} (expected 200)"
  fi
else
  fail "Central route not found"
fi

echo "--- Step 4: Init-bundle job ---"
JOB_STATUS=$(oc get job -n "$NS" -l app=stackrox-init-bundle -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null || echo "0")
if [ "$JOB_STATUS" = "1" ]; then
  pass "Init-bundle job completed"
else
  fail "Init-bundle job not completed (succeeded=$JOB_STATUS)"
fi

echo "--- Step 5: Scanner pods ---"
SCANNER_PODS=$(oc get pods -n "$NS" -l app=scanner --no-headers 2>/dev/null | wc -l | tr -d ' ')
SCANNER_NOT_READY=$(oc get pods -n "$NS" -l app=scanner --no-headers 2>/dev/null | grep -cv "Running" || true)
if [ "$SCANNER_PODS" -gt 0 ] && [ "$SCANNER_NOT_READY" -eq 0 ]; then
  pass "All ${SCANNER_PODS} scanner pods running"
else
  fail "${SCANNER_NOT_READY} of ${SCANNER_PODS} scanner pods not running"
fi

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
