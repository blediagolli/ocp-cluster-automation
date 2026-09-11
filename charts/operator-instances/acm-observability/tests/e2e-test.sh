#!/bin/bash
set -euo pipefail

# ACM Observability E2E Test
# Validates Thanos components, OBC, Grafana route, and metrics endpoint
#
# Usage: ./e2e-test.sh [namespace]
# Example: ./e2e-test.sh open-cluster-management-observability

NAMESPACE="${1:-open-cluster-management-observability}"
PASSED=0
FAILED=0
TOTAL=6

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }

echo "=== ACM Observability E2E Test ==="
echo "  Namespace: ${NAMESPACE}"
echo ""

# 1. Check MCO CR
echo "--- Step 1: MultiClusterObservability CR ---"
MCO_STATUS=$(oc get multiclusterobservability observability -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
if [ "${MCO_STATUS}" = "True" ]; then
  pass "MCO Ready: ${MCO_STATUS}"
else
  fail "MCO Ready: ${MCO_STATUS:-not found}"
fi

# 2. Check Thanos components
echo "--- Step 2: Thanos components ---"
COMPONENTS=("observability-thanos-query" "observability-thanos-receive" "observability-thanos-compact" "observability-thanos-store-shard" "observability-thanos-rule")
THANOS_OK=true
for COMP in "${COMPONENTS[@]}"; do
  READY=$(oc get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | grep "${COMP}" | grep -c Running || true)
  if [ "${READY}" -ge 1 ]; then
    echo "    ${COMP}: ${READY} running"
  else
    echo "    ${COMP}: NOT RUNNING"
    THANOS_OK=false
  fi
done
if [ "${THANOS_OK}" = "true" ]; then
  pass "All Thanos components running"
else
  fail "Some Thanos components not running"
fi

# 3. Check ObjectBucketClaim
echo "--- Step 3: ObjectBucketClaim ---"
OBC_PHASE=$(oc get objectbucketclaim -n "${NAMESPACE}" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
if [ "${OBC_PHASE}" = "Bound" ]; then
  pass "OBC phase: Bound"
else
  fail "OBC phase: ${OBC_PHASE:-not found}"
fi

# 4. Check Grafana route
echo "--- Step 4: Grafana route ---"
GRAFANA_HOST=$(oc get route -n "${NAMESPACE}" grafana -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "${GRAFANA_HOST}" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -k "https://${GRAFANA_HOST}" --connect-timeout 10 || echo "000")
  if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "302" ] || [ "${HTTP_CODE}" = "403" ]; then
    pass "Grafana route: https://${GRAFANA_HOST} (HTTP ${HTTP_CODE})"
  else
    fail "Grafana route returned HTTP ${HTTP_CODE}"
  fi
else
  fail "Grafana route not found"
fi

# 5. Check object storage secret
echo "--- Step 5: Object storage secret ---"
SECRET=$(oc get secret thanos-object-storage -n "${NAMESPACE}" -o name 2>/dev/null || echo "")
if [ -n "${SECRET}" ]; then
  pass "Object storage secret exists"
else
  fail "Object storage secret not found"
fi

# 6. Check metrics endpoint
echo "--- Step 6: Observability addon on managed clusters ---"
ADDON_COUNT=$(oc get managedclusteraddon --all-namespaces --no-headers 2>/dev/null | grep -c "observability-controller" || true)
if [ "${ADDON_COUNT}" -ge 1 ]; then
  pass "Observability addon deployed on ${ADDON_COUNT} cluster(s)"
else
  fail "No observability addon found on managed clusters"
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
