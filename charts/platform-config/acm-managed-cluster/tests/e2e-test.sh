#!/bin/bash
set -uo pipefail

# ACM Managed Cluster E2E Test
# Validates ManagedCluster join, availability, addons, and ArgoCD registration
#
# Usage: ./e2e-test.sh <cluster-name>
# Example: ./e2e-test.sh cluster-lz5bn

CLUSTER="${1:?Usage: $0 <cluster-name>}"
PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

echo "=== ACM Managed Cluster E2E Test ==="
echo "  Cluster: ${CLUSTER}"
echo ""

# 1. Check ManagedCluster exists
echo "--- Step 1: ManagedCluster resource ---"
MC_EXISTS=$(oc get managedcluster "${CLUSTER}" -o name 2>/dev/null || echo "")
if [ -n "${MC_EXISTS}" ]; then
  pass "ManagedCluster ${CLUSTER} exists"
else
  fail "ManagedCluster ${CLUSTER} not found"
  echo ""
  echo "=== Results ==="
  echo "  ${PASSED}/${TOTAL} passed, ${FAILED} failed"
  echo "  E2E TEST FAILED"
  exit 1
fi

# 2. Check joined condition
echo "--- Step 2: Joined condition ---"
JOINED=$(oc get managedcluster "${CLUSTER}" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterJoined")].status}' 2>/dev/null || echo "")
if [ "${JOINED}" = "True" ]; then
  pass "Cluster joined"
else
  fail "Cluster not joined (status: ${JOINED:-unknown})"
fi

# 3. Check available condition
echo "--- Step 3: Available condition ---"
AVAILABLE=$(oc get managedcluster "${CLUSTER}" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}' 2>/dev/null || echo "")
if [ "${AVAILABLE}" = "True" ]; then
  pass "Cluster available"
else
  fail "Cluster not available (status: ${AVAILABLE:-unknown})"
fi

# 4. Check ManagedClusterAddOns
echo "--- Step 4: ManagedClusterAddOns ---"
ADDONS=$(oc get managedclusteraddon -n "${CLUSTER}" --no-headers 2>/dev/null || echo "")
if [ -n "${ADDONS}" ]; then
  ADDON_COUNT=$(echo "${ADDONS}" | wc -l | tr -d ' ')
  AVAILABLE_COUNT=$(echo "${ADDONS}" | grep -c "True" || true)
  echo "    Total addons: ${ADDON_COUNT}"
  echo "    Available: ${AVAILABLE_COUNT}"
  while IFS= read -r line; do
    ADDON_NAME=$(echo "${line}" | awk '{print $1}')
    ADDON_STATUS=$(oc get managedclusteraddon "${ADDON_NAME}" -n "${CLUSTER}" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
    echo "    ${ADDON_NAME}: ${ADDON_STATUS}"
  done <<< "${ADDONS}"
  if [ "${AVAILABLE_COUNT}" -ge 1 ]; then
    pass "AddOns available: ${AVAILABLE_COUNT}/${ADDON_COUNT}"
  else
    fail "No addons available"
  fi
else
  fail "No ManagedClusterAddOns found"
fi

# 5. Check ArgoCD cluster secret
echo "--- Step 5: ArgoCD cluster registration ---"
ARGO_SECRET=$(oc get secret -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster --no-headers 2>/dev/null | grep "${CLUSTER}" || true)
if [ -n "${ARGO_SECRET}" ]; then
  pass "ArgoCD cluster secret found for ${CLUSTER}"
else
  fail "ArgoCD cluster secret not found for ${CLUSTER}"
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
