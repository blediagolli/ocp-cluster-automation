#!/bin/bash
set -uo pipefail

# OpenShift GitOps Instance E2E Test
# Validates ArgoCD instance, AppProject, route, and RBAC.
#
# Usage: ./e2e-test.sh [namespace]
# Default namespace: openshift-gitops

NS="${1:-openshift-gitops}"
PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

echo "=== OpenShift GitOps Instance E2E Test ==="
echo "  Namespace: ${NS}"
echo ""

echo "--- Step 1: ArgoCD CR status ---"
PHASE=$(oc get argocd openshift-gitops -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$PHASE" = "Available" ]; then
  pass "ArgoCD CR phase=Available"
else
  fail "ArgoCD CR phase=$PHASE (expected Available)"
fi

echo "--- Step 2: ArgoCD pods running ---"
TOTAL_PODS=$(oc get pods -n "$NS" --no-headers 2>/dev/null | grep "^openshift-gitops-" | wc -l | tr -d ' ')
NOT_READY=$(oc get pods -n "$NS" --no-headers 2>/dev/null | grep "^openshift-gitops-" | grep -cv "Running" || true)
if [ "$TOTAL_PODS" -gt 0 ] && [ "$NOT_READY" -eq 0 ]; then
  pass "All ${TOTAL_PODS} ArgoCD pods running"
else
  fail "${NOT_READY} of ${TOTAL_PODS} ArgoCD pods not running"
fi

echo "--- Step 3: ArgoCD route accessible ---"
ROUTE=$(oc get route openshift-gitops-server -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$ROUTE" ]; then
  HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "https://${ROUTE}" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
    pass "Route https://${ROUTE} returned HTTP ${HTTP_CODE}"
  else
    fail "Route https://${ROUTE} returned HTTP ${HTTP_CODE}"
  fi
else
  fail "Route openshift-gitops-server not found"
fi

echo "--- Step 4: AppProject exists ---"
if oc get appproject platform -n "$NS" &>/dev/null; then
  pass "AppProject 'platform' exists"
else
  fail "AppProject 'platform' not found"
fi

echo "--- Step 5: ClusterRoleBinding ---"
if oc get clusterrolebinding openshift-gitops-argocd-cluster-admin &>/dev/null; then
  pass "ClusterRoleBinding exists"
else
  fail "ClusterRoleBinding openshift-gitops-argocd-cluster-admin not found"
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
