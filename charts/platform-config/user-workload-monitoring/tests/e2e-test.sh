#!/bin/bash
set -uo pipefail

# User Workload Monitoring E2E Test
# Validates Prometheus UWM pods, ConfigMaps, and optional ServiceMonitor scraping
#
# Usage: ./e2e-test.sh
# Example: ./e2e-test.sh

PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

echo "=== User Workload Monitoring E2E Test ==="
echo ""

# 1. Check cluster-monitoring-config
echo "--- Step 1: cluster-monitoring-config ---"
UW_ENABLED=$(oc get configmap cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\.yaml}' 2>/dev/null | grep -c "enableUserWorkload: true" || true)
if [ "${UW_ENABLED}" -ge 1 ]; then
  pass "enableUserWorkload: true in cluster-monitoring-config"
else
  fail "enableUserWorkload not set in cluster-monitoring-config"
fi

# 2. Check user-workload-monitoring-config
echo "--- Step 2: user-workload-monitoring-config ---"
UWM_CM=$(oc get configmap user-workload-monitoring-config -n openshift-user-workload-monitoring -o name 2>/dev/null || echo "")
if [ -n "${UWM_CM}" ]; then
  pass "user-workload-monitoring-config exists"
else
  fail "user-workload-monitoring-config not found"
fi

# 3. Check Prometheus UWM pods
echo "--- Step 3: Prometheus user-workload pods ---"
PROM_PODS=$(oc get pods -n openshift-user-workload-monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c Running || true)
if [ "${PROM_PODS}" -ge 1 ]; then
  pass "Prometheus pods running: ${PROM_PODS}"
else
  fail "No Prometheus pods running"
fi

# 4. Check Thanos Ruler (if present)
echo "--- Step 4: Thanos Ruler ---"
TR_PODS=$(oc get pods -n openshift-user-workload-monitoring -l app.kubernetes.io/name=thanos-ruler --no-headers 2>/dev/null | grep -c Running || true)
if [ "${TR_PODS}" -ge 1 ]; then
  pass "Thanos Ruler pods running: ${TR_PODS}"
else
  TR_EXPECTED=$(oc get configmap user-workload-monitoring-config -n openshift-user-workload-monitoring -o jsonpath='{.data.config\.yaml}' 2>/dev/null | grep -c "thanosRuler" || true)
  if [ "${TR_EXPECTED}" -ge 1 ]; then
    fail "Thanos Ruler configured but no pods running"
  else
    pass "Thanos Ruler not configured (expected)"
  fi
fi

# 5. Check metrics availability
echo "--- Step 5: Metrics endpoint ---"
SA_TOKEN=$(oc whoami -t 2>/dev/null || echo "")
if [ -n "${SA_TOKEN}" ]; then
  THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  if [ -n "${THANOS_HOST}" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -k \
      -H "Authorization: Bearer ${SA_TOKEN}" \
      "https://${THANOS_HOST}/api/v1/query?query=up" --connect-timeout 10 || echo "000")
    if [ "${HTTP_CODE}" = "200" ]; then
      pass "Thanos querier returning metrics (HTTP ${HTTP_CODE})"
    else
      fail "Thanos querier returned HTTP ${HTTP_CODE}"
    fi
  else
    fail "Thanos querier route not found"
  fi
else
  fail "Could not create SA token for metrics query"
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
