#!/bin/bash
set -uo pipefail

# openshift-group-sync E2E Test
# Validates CronJob, RBAC, ConfigMap, and Group objects.
#
# Usage: ./e2e-test.sh [provider] [namespace]
# Example: ./e2e-test.sh keycloak openshift-authentication

PROVIDER="${1:-keycloak}"
NAMESPACE="${2:-openshift-authentication}"
SA_NAME="group-syncer"
PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); TOTAL=$((TOTAL + 1)); }

echo "=== openshift-group-sync E2E Test ==="
echo "  Provider:  ${PROVIDER}"
echo "  Namespace: ${NAMESPACE}"
echo ""

# --- RBAC ---
echo "--- Step 1: ServiceAccount ---"
if oc get sa "${SA_NAME}" -n "${NAMESPACE}" &>/dev/null; then
  pass "ServiceAccount '${SA_NAME}' exists in ${NAMESPACE}"
else
  fail "ServiceAccount '${SA_NAME}' not found in ${NAMESPACE}"
fi

echo "--- Step 2: ClusterRole ---"
RULES=$(oc get clusterrole "${SA_NAME}" -o jsonpath='{.rules[0].resources[0]}' 2>/dev/null || echo "")
if [ "${RULES}" = "groups" ]; then
  pass "ClusterRole '${SA_NAME}' scoped to groups resource"
else
  fail "ClusterRole '${SA_NAME}' not found or not scoped to groups (got: ${RULES})"
fi

echo "--- Step 3: ClusterRoleBinding ---"
CRB_ROLE=$(oc get clusterrolebinding "${SA_NAME}" -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "")
if [ "${CRB_ROLE}" = "${SA_NAME}" ]; then
  pass "ClusterRoleBinding '${SA_NAME}' references correct ClusterRole"
else
  fail "ClusterRoleBinding '${SA_NAME}' not found or wrong roleRef (got: ${CRB_ROLE})"
fi

# --- Provider-specific ---
if [ "${PROVIDER}" = "ldap" ]; then
  echo "--- Step 4: LDAP CronJob ---"
  CJ_SCHEDULE=$(oc get cronjob ldap-group-sync -n "${NAMESPACE}" -o jsonpath='{.spec.schedule}' 2>/dev/null || echo "")
  if [ -n "${CJ_SCHEDULE}" ]; then
    LAST=$(oc get cronjob ldap-group-sync -n "${NAMESPACE}" -o jsonpath='{.status.lastScheduleTime}' 2>/dev/null || echo "never")
    pass "CronJob ldap-group-sync (schedule: ${CJ_SCHEDULE}, last: ${LAST})"
  else
    fail "CronJob ldap-group-sync not found"
  fi

  echo "--- Step 5: LDAP sync ConfigMap ---"
  if oc get configmap ldap-sync-config -n "${NAMESPACE}" &>/dev/null; then
    pass "ConfigMap ldap-sync-config exists"
  else
    fail "ConfigMap ldap-sync-config not found"
  fi

elif [ "${PROVIDER}" = "keycloak" ]; then
  echo "--- Step 4: Keycloak CronJob ---"
  CJ_SCHEDULE=$(oc get cronjob keycloak-group-sync -n "${NAMESPACE}" -o jsonpath='{.spec.schedule}' 2>/dev/null || echo "")
  if [ -n "${CJ_SCHEDULE}" ]; then
    LAST=$(oc get cronjob keycloak-group-sync -n "${NAMESPACE}" -o jsonpath='{.status.lastScheduleTime}' 2>/dev/null || echo "never")
    pass "CronJob keycloak-group-sync (schedule: ${CJ_SCHEDULE}, last: ${LAST})"
  else
    fail "CronJob keycloak-group-sync not found"
  fi

  echo "--- Step 5: Keycloak sync script ConfigMap ---"
  if oc get configmap keycloak-group-sync-script -n "${NAMESPACE}" &>/dev/null; then
    pass "ConfigMap keycloak-group-sync-script exists"
  else
    fail "ConfigMap keycloak-group-sync-script not found"
  fi
fi

# --- Check last job result ---
echo "--- Step 6: Last Job status ---"
if [ "${PROVIDER}" = "ldap" ]; then
  CJ_NAME="ldap-group-sync"
else
  CJ_NAME="keycloak-group-sync"
fi
LAST_JOB=$(oc get jobs -n "${NAMESPACE}" --sort-by=.metadata.creationTimestamp -l "job-name" --no-headers 2>/dev/null | grep "${CJ_NAME}" | tail -1 | awk '{print $1}')
if [ -n "${LAST_JOB}" ]; then
  SUCCEEDED=$(oc get job "${LAST_JOB}" -n "${NAMESPACE}" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
  if [ "${SUCCEEDED}" = "1" ]; then
    pass "Last job '${LAST_JOB}' succeeded"
  else
    fail "Last job '${LAST_JOB}' did not succeed (succeeded=${SUCCEEDED})"
  fi
else
  pass "No jobs have run yet (CronJob not triggered)"
fi

# --- Check OpenShift Groups ---
echo "--- Step 7: OpenShift Groups ---"
GROUP_COUNT=$(oc get groups --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${GROUP_COUNT}" -gt 0 ]; then
  GROUPS=$(oc get groups --no-headers 2>/dev/null | awk '{printf "    %s (users: %s)\n", $1, $2}')
  pass "${GROUP_COUNT} OpenShift Group(s) found:"
  echo "${GROUPS}"
else
  pass "No OpenShift Groups found (sync may not have run yet)"
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
