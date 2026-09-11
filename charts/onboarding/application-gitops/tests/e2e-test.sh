#!/bin/bash
set -uo pipefail

# application-gitops E2E Test
# Validates team ArgoCD instance, AppProject configuration, namespace, and
# RBAC are correctly provisioned.
#
# Usage: ./e2e-test.sh <team-name>
# Example: ./e2e-test.sh team-alpha

TEAM="${1:?Usage: $0 <team-name>}"
NS="${TEAM}-gitops"
PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

echo "=== application-gitops E2E Test ==="
echo "  Team:      ${TEAM}"
echo "  Namespace: ${NS}"
echo ""

echo "--- Step 1: Namespace exists ---"
if oc get namespace "${NS}" &>/dev/null; then
  pass "Namespace ${NS} exists"
else
  fail "Namespace ${NS} not found"
fi

echo "--- Step 2: ArgoCD instance available ---"
ARGOCD_PHASE=$(oc get argocd "${TEAM}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "${ARGOCD_PHASE}" = "Available" ]; then
  pass "ArgoCD instance is Available"
else
  fail "ArgoCD instance phase is '${ARGOCD_PHASE}', expected 'Available'"
fi

echo "--- Step 3: ArgoCD server route ---"
ROUTE_HOST=$(oc get route "${TEAM}-server" -n "${NS}" -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "${ROUTE_HOST}" ]; then
  pass "Server route exists: ${ROUTE_HOST}"
else
  fail "Server route not found"
fi

echo "--- Step 4: AppProject configuration ---"
SOURCE_REPOS=$(oc get appproject "${TEAM}" -n "${NS}" -o jsonpath='{.spec.sourceRepos[*]}' 2>/dev/null)
DEST_COUNT=$(oc get appproject "${TEAM}" -n "${NS}" -o jsonpath='{.spec.destinations}' 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ -n "${SOURCE_REPOS}" ] && [ "${DEST_COUNT}" -ge 1 ]; then
  pass "AppProject has sourceRepos and ${DEST_COUNT} destination(s)"
else
  fail "AppProject missing sourceRepos or destinations"
fi

echo "--- Step 5: RoleBinding grants admin ---"
RB_GROUP=$(oc get rolebinding "${TEAM}-admin" -n "${NS}" -o jsonpath='{.subjects[0].name}' 2>/dev/null)
if [ -n "${RB_GROUP}" ]; then
  pass "RoleBinding grants admin to group '${RB_GROUP}'"
else
  fail "RoleBinding ${TEAM}-admin not found or has no subjects"
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
