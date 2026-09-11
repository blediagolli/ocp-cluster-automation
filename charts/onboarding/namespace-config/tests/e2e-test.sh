#!/bin/bash
set -euo pipefail

# namespace-config E2E Test
# Validates team namespaces are created with correct labels, ResourceQuota
# matching the size tier, and LimitRange applied.
#
# Usage: ./e2e-test.sh <team-name> <environment>
# Example: ./e2e-test.sh team-alpha dev

TEAM="${1:?Usage: $0 <team-name> <environment>}"
ENV="${2:?Usage: $0 <team-name> <environment>}"
PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }

echo "=== namespace-config E2E Test ==="
echo "  Team:        ${TEAM}"
echo "  Environment: ${ENV}"
echo ""

NAMESPACES=$(oc get namespaces -l "argocd.argoproj.io/managed-by=${TEAM}-gitops" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

if [ -z "${NAMESPACES}" ]; then
  echo "  FAIL: No namespaces found with label argocd.argoproj.io/managed-by=${TEAM}-gitops"
  echo ""
  echo "=== Results ==="
  echo "  0/0 passed, 1 failed"
  echo "  E2E TEST FAILED"
  exit 1
fi

while IFS= read -r ns; do
  [ -z "${ns}" ] && continue
  echo "--- Namespace: ${ns} ---"

  TOTAL=$((TOTAL + 1))
  echo "  Checking namespace exists..."
  if oc get namespace "${ns}" &>/dev/null; then
    pass "Namespace ${ns} exists"
  else
    fail "Namespace ${ns} not found"
    continue
  fi

  TOTAL=$((TOTAL + 1))
  SIZE=$(oc get namespace "${ns}" -o jsonpath='{.metadata.labels.namespace-size}' 2>/dev/null)
  if [ -n "${SIZE}" ]; then
    pass "namespace-size label is '${SIZE}'"
  else
    fail "namespace-size label missing on ${ns}"
  fi

  TOTAL=$((TOTAL + 1))
  if oc get resourcequota team-quota -n "${ns}" &>/dev/null; then
    RQ_SIZE=$(oc get resourcequota team-quota -n "${ns}" -o jsonpath='{.metadata.labels.namespace-size}' 2>/dev/null)
    if [ "${RQ_SIZE}" = "${SIZE}" ]; then
      pass "ResourceQuota team-quota matches size '${SIZE}'"
    else
      fail "ResourceQuota size label '${RQ_SIZE}' does not match namespace size '${SIZE}'"
    fi
  else
    fail "ResourceQuota team-quota not found in ${ns}"
  fi

  TOTAL=$((TOTAL + 1))
  if oc get limitrange team-limits -n "${ns}" &>/dev/null; then
    LR_SIZE=$(oc get limitrange team-limits -n "${ns}" -o jsonpath='{.metadata.labels.namespace-size}' 2>/dev/null)
    if [ "${LR_SIZE}" = "${SIZE}" ]; then
      pass "LimitRange team-limits matches size '${SIZE}'"
    else
      fail "LimitRange size label '${LR_SIZE}' does not match namespace size '${SIZE}'"
    fi
  else
    fail "LimitRange team-limits not found in ${ns}"
  fi
  echo ""
done <<< "${NAMESPACES}"

echo "=== Results ==="
echo "  ${PASSED}/${TOTAL} passed, ${FAILED} failed"
if [ "${FAILED}" -eq 0 ]; then
  echo "  E2E TEST PASSED"
  exit 0
else
  echo "  E2E TEST FAILED"
  exit 1
fi
