#!/bin/bash
set -euo pipefail

# ACM MultiClusterHub E2E Test
# Validates MCH phase, components, assisted-service, hive, and GitOpsCluster.
#
# Usage: ./e2e-test.sh [namespace]
# Default namespace: open-cluster-management

NS="${1:-open-cluster-management}"
PASSED=0
FAILED=0
TOTAL=6

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }

echo "=== ACM MultiClusterHub E2E Test ==="
echo "  Namespace: ${NS}"
echo ""

echo "--- Step 1: MCH status ---"
PHASE=$(oc get multiclusterhub multiclusterhub -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$PHASE" = "Running" ]; then
  pass "MCH phase=Running"
else
  fail "MCH phase=$PHASE (expected Running)"
fi

echo "--- Step 2: MCH components ---"
COMPONENTS=$(oc get multiclusterhub multiclusterhub -n "$NS" -o jsonpath='{.status.components}' 2>/dev/null || echo "{}")
DEGRADED=$(echo "$COMPONENTS" | jq '[to_entries[] | select(.value.status != "True")] | length' 2>/dev/null || echo "-1")
COMP_TOTAL=$(echo "$COMPONENTS" | jq '[to_entries[]] | length' 2>/dev/null || echo "0")
if [ "$DEGRADED" -eq 0 ] && [ "$COMP_TOTAL" -gt 0 ]; then
  pass "All ${COMP_TOTAL} MCH components healthy"
else
  fail "${DEGRADED} of ${COMP_TOTAL} MCH components not ready"
fi

echo "--- Step 3: Assisted service ---"
if oc get agentserviceconfig agent -n "$NS" &>/dev/null; then
  READY=$(oc get agentserviceconfig agent -o jsonpath='{.status.conditions[?(@.type=="ReconcileCompleted")].status}' 2>/dev/null || echo "Unknown")
  if [ "$READY" = "True" ]; then
    pass "AgentServiceConfig reconciled"
  else
    fail "AgentServiceConfig not reconciled (status=$READY)"
  fi
else
  fail "AgentServiceConfig not found"
fi

echo "--- Step 4: Hive ---"
if oc get hiveconfig hive &>/dev/null; then
  READY=$(oc get hiveconfig hive -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
  if [ "$READY" = "True" ]; then
    pass "HiveConfig ready"
  else
    fail "HiveConfig not ready (status=$READY)"
  fi
else
  fail "HiveConfig not found"
fi

echo "--- Step 5: GitOpsCluster ---"
if oc get gitopscluster argo-acm-clusters -n openshift-gitops &>/dev/null; then
  REGISTERED=$(oc get gitopscluster argo-acm-clusters -n openshift-gitops -o jsonpath='{.status.conditions[?(@.type=="ClustersRegistered")].status}' 2>/dev/null || echo "Unknown")
  if [ "$REGISTERED" = "True" ]; then
    pass "GitOpsCluster ClustersRegistered=True"
  else
    fail "GitOpsCluster ClustersRegistered=$REGISTERED"
  fi
else
  fail "GitOpsCluster argo-acm-clusters not found"
fi

echo "--- Step 6: Managed clusters visible ---"
MC_COUNT=$(oc get managedclusters --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$MC_COUNT" -gt 0 ]; then
  pass "${MC_COUNT} ManagedCluster(s) registered"
else
  fail "No ManagedClusters found"
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
