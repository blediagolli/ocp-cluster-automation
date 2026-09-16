#!/bin/bash
set -uo pipefail

# Cluster Provisioning E2E Test
# Validates that a provisioned cluster's resources exist and are in expected states.
#
# Usage: ./e2e-test.sh <cluster-name>
# Example: ./e2e-test.sh aws-none-prod

CLUSTER="${1:?Usage: $0 <cluster-name>}"
PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); TOTAL=$((TOTAL + 1)); }
skip() { echo "  SKIP: $1"; TOTAL=$((TOTAL + 1)); }

echo "=== Cluster Provisioning E2E Test ==="
echo "  Cluster: ${CLUSTER}"
echo ""

# 1. Namespace
echo "--- Step 1: Namespace ---"
NS_EXISTS=$(oc get namespace "${CLUSTER}" -o name 2>/dev/null || echo "")
if [ -n "${NS_EXISTS}" ]; then
  pass "Namespace ${CLUSTER} exists"
else
  fail "Namespace ${CLUSTER} not found"
  echo ""
  echo "=== Results ==="
  echo "  ${PASSED}/${TOTAL} passed, ${FAILED} failed"
  echo "  E2E TEST FAILED"
  exit 1
fi

# 2. ClusterDeployment
echo "--- Step 2: ClusterDeployment ---"
CD_EXISTS=$(oc get clusterdeployment.hive.openshift.io "${CLUSTER}" -n "${CLUSTER}" -o name 2>/dev/null || echo "")
if [ -n "${CD_EXISTS}" ]; then
  pass "ClusterDeployment exists"
else
  fail "ClusterDeployment not found"
fi

# Detect platform type from ClusterDeployment label
PLATFORM_LABEL=$(oc get clusterdeployment.hive.openshift.io "${CLUSTER}" -n "${CLUSTER}" -o jsonpath='{.metadata.labels.hive\.openshift\.io/cluster-platform}' 2>/dev/null || echo "")
IS_AGENT=false
if [ "$PLATFORM_LABEL" = "agent-baremetal" ]; then
  IS_AGENT=true
fi
echo "    Platform label: ${PLATFORM_LABEL:-unknown} (agent-based: ${IS_AGENT})"

# 3. ClusterDeployment conditions
echo "--- Step 3: ClusterDeployment status ---"
CD_INSTALLED=$(oc get clusterdeployment.hive.openshift.io "${CLUSTER}" -n "${CLUSTER}" -o jsonpath='{.spec.installed}' 2>/dev/null || echo "")
echo "    installed: ${CD_INSTALLED:-not set}"

# 4. ManagedCluster
echo "--- Step 4: ManagedCluster ---"
MC_EXISTS=$(oc get managedcluster "${CLUSTER}" -o name 2>/dev/null || echo "")
if [ -n "${MC_EXISTS}" ]; then
  pass "ManagedCluster exists"
  JOINED=$(oc get managedcluster "${CLUSTER}" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterJoined")].status}' 2>/dev/null || echo "")
  if [ "${JOINED}" = "True" ]; then
    pass "ManagedCluster joined"
  else
    skip "ManagedCluster not yet joined (status: ${JOINED:-unknown})"
  fi
else
  fail "ManagedCluster not found"
fi

# 5. KlusterletAddonConfig
echo "--- Step 5: KlusterletAddonConfig ---"
KAC_EXISTS=$(oc get klusterletaddonconfig "${CLUSTER}" -n "${CLUSTER}" -o name 2>/dev/null || echo "")
if [ -n "${KAC_EXISTS}" ]; then
  pass "KlusterletAddonConfig exists"
else
  fail "KlusterletAddonConfig not found"
fi

# 6. Pull secret
echo "--- Step 6: Pull secret ---"
PS_EXISTS=$(oc get secret "${CLUSTER}-pull-secret" -n "${CLUSTER}" -o name 2>/dev/null || echo "")
if [ -n "${PS_EXISTS}" ]; then
  pass "Pull secret exists"
else
  fail "Pull secret not found"
fi

# 7. Agent-based resources
echo "--- Step 7: Agent-based resources ---"
if [ "${IS_AGENT}" = "true" ]; then
  ACI_EXISTS=$(oc get agentclusterinstall "${CLUSTER}" -n "${CLUSTER}" -o name 2>/dev/null || echo "")
  if [ -n "${ACI_EXISTS}" ]; then
    pass "AgentClusterInstall exists"
  else
    fail "AgentClusterInstall not found (expected for agent-based)"
  fi

  IE_EXISTS=$(oc get infraenv "${CLUSTER}" -n "${CLUSTER}" -o name 2>/dev/null || echo "")
  if [ -n "${IE_EXISTS}" ]; then
    pass "InfraEnv exists"
  else
    fail "InfraEnv not found (expected for agent-based)"
  fi

  BMH_COUNT=$(oc get baremetalhost -n "${CLUSTER}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "${BMH_COUNT}" -ge 1 ]; then
    pass "BareMetalHosts found: ${BMH_COUNT}"
  else
    fail "No BareMetalHosts found (expected for agent-based)"
  fi
else
  skip "Agent resources: skipped (IPI platform)"
fi

# 8. IPI resources
echo "--- Step 8: IPI resources ---"
if [ "${IS_AGENT}" = "false" ]; then
  MP_EXISTS=$(oc get machinepool "${CLUSTER}-worker" -n "${CLUSTER}" -o name 2>/dev/null || echo "")
  if [ -n "${MP_EXISTS}" ]; then
    pass "MachinePool exists"
  else
    fail "MachinePool not found (expected for IPI)"
  fi

  IC_EXISTS=$(oc get secret "${CLUSTER}-install-config" -n "${CLUSTER}" -o name 2>/dev/null || echo "")
  if [ -n "${IC_EXISTS}" ]; then
    pass "Install config secret exists"
  else
    fail "Install config secret not found (expected for IPI)"
  fi
else
  skip "IPI resources: skipped (agent-based platform)"
fi

# 9. ArgoCD Application sync status
echo "--- Step 9: ArgoCD Application ---"
ARGO_APP=$(oc get application -n openshift-gitops --no-headers 2>/dev/null | grep "provision.*${CLUSTER}" | head -1 || true)
if [ -n "${ARGO_APP}" ]; then
  APP_NAME=$(echo "${ARGO_APP}" | awk '{print $1}')
  SYNC_STATUS=$(oc get application "${APP_NAME}" -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
  HEALTH_STATUS=$(oc get application "${APP_NAME}" -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
  echo "    App: ${APP_NAME}"
  echo "    Sync: ${SYNC_STATUS}, Health: ${HEALTH_STATUS}"
  if [ "${SYNC_STATUS}" = "Synced" ]; then
    pass "ArgoCD Application is Synced"
  else
    fail "ArgoCD Application sync status: ${SYNC_STATUS} (expected Synced)"
  fi
else
  skip "No ArgoCD provisioning Application found for ${CLUSTER}"
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
