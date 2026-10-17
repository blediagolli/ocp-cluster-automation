#!/bin/bash
set -uo pipefail

# ACS SecuredCluster E2E Test
# Validates sensor, collector, admission-control, and Central connection.
#
# Usage: ./e2e-test.sh [namespace]
# Default namespace: stackrox

NS="${1:-stackrox}"
PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

echo "=== ACS SecuredCluster E2E Test ==="
echo "  Namespace: ${NS}"
echo ""

echo "--- Step 1: SecuredCluster CR status ---"
DEPLOYED=$(oc get securedcluster stackrox-secured-cluster-services -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="Deployed")].status}' 2>/dev/null || echo "NotFound")
if [ "$DEPLOYED" = "True" ]; then
  pass "SecuredCluster Deployed=True"
else
  fail "SecuredCluster Deployed=$DEPLOYED (expected True)"
fi

echo "--- Step 2: Sensor pods ---"
SENSOR_PODS=$(oc get pods -n "$NS" -l app=sensor --no-headers 2>/dev/null | wc -l | tr -d ' ')
SENSOR_NOT_READY=$(oc get pods -n "$NS" -l app=sensor --no-headers 2>/dev/null | grep -cv "Running" || true)
if [ "$SENSOR_PODS" -gt 0 ] && [ "$SENSOR_NOT_READY" -eq 0 ]; then
  pass "All ${SENSOR_PODS} sensor pods running"
else
  fail "Sensor: ${SENSOR_NOT_READY} of ${SENSOR_PODS} pods not running"
fi

echo "--- Step 3: Collector daemonset ---"
DESIRED=$(oc get daemonset collector -n "$NS" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
READY=$(oc get daemonset collector -n "$NS" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
if [ "$DESIRED" -gt 0 ] && [ "$DESIRED" = "$READY" ]; then
  pass "Collector daemonset ${READY}/${DESIRED} ready"
else
  fail "Collector daemonset ${READY}/${DESIRED} ready"
fi

echo "--- Step 4: Admission control ---"
AC_PODS=$(oc get pods -n "$NS" -l app=admission-control --no-headers 2>/dev/null | wc -l | tr -d ' ')
AC_NOT_READY=$(oc get pods -n "$NS" -l app=admission-control --no-headers 2>/dev/null | grep -cv "Running" || true)
if [ "$AC_PODS" -gt 0 ] && [ "$AC_NOT_READY" -eq 0 ]; then
  pass "All ${AC_PODS} admission-control pods running"
else
  fail "Admission control: ${AC_NOT_READY} of ${AC_PODS} pods not running"
fi

echo "--- Step 5: Sensor Central connection ---"
SENSOR_LOG=$(oc logs -n "$NS" -l app=sensor --tail=50 2>/dev/null || echo "")
if echo "$SENSOR_LOG" | grep -qi "connected to central"; then
  pass "Sensor connected to Central"
else
  INIT_STATUS=$(oc get securedcluster stackrox-secured-cluster-services -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="Initialized")].status}' 2>/dev/null || echo "Unknown")
  if [ "$INIT_STATUS" = "True" ]; then
    pass "SecuredCluster Initialized=True (connection likely active)"
  else
    fail "Cannot confirm Central connection (Initialized=$INIT_STATUS)"
  fi
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
