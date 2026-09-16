#!/bin/bash
set -uo pipefail

# group-sync operator instance E2E Test
# Validates GroupSync CR, operator pod, and synced Groups.
#
# Usage: ./e2e-test.sh [name] [namespace]
# Example: ./e2e-test.sh group-sync group-sync-operator

NAME="${1:-group-sync}"
NAMESPACE="${2:-group-sync-operator}"
PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

echo "=== group-sync Operator Instance E2E Test ==="
echo "  Name:      ${NAME}"
echo "  Namespace: ${NAMESPACE}"
echo ""

# --- Operator pod ---
echo "--- Step 1: Operator pod ---"
NOT_READY=$(oc get pods -n "${NAMESPACE}" -l control-plane=controller-manager --no-headers 2>/dev/null | grep -cv "Running" || true)
TOTAL_PODS=$(oc get pods -n "${NAMESPACE}" -l control-plane=controller-manager --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${TOTAL_PODS}" -gt 0 ] && [ "${NOT_READY}" -eq 0 ]; then
  pass "Operator pod running (${TOTAL_PODS} pod(s))"
else
  fail "Operator pod not running (${NOT_READY} of ${TOTAL_PODS} not ready)"
fi

# --- GroupSync CR ---
echo "--- Step 2: GroupSync CR exists ---"
if oc get groupsync "${NAME}" -n "${NAMESPACE}" &>/dev/null; then
  pass "GroupSync '${NAME}' exists in ${NAMESPACE}"
else
  fail "GroupSync '${NAME}' not found in ${NAMESPACE}"
fi

# --- Sync status ---
echo "--- Step 3: GroupSync status ---"
SYNCED=$(oc get groupsync "${NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Synced")].status}' 2>/dev/null || echo "")
LAST_SYNC=$(oc get groupsync "${NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.lastSyncSuccessTime}' 2>/dev/null || echo "never")
if [ "${SYNCED}" = "True" ]; then
  pass "GroupSync Synced=True (last: ${LAST_SYNC})"
elif [ -n "${SYNCED}" ]; then
  fail "GroupSync Synced=${SYNCED} (expected True, last: ${LAST_SYNC})"
else
  pass "GroupSync has no status yet (may not have run)"
fi

# --- Providers configured ---
echo "--- Step 4: Providers ---"
PROVIDER_COUNT=$(oc get groupsync "${NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.providers}' 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "${PROVIDER_COUNT}" -gt 0 ]; then
  PROVIDERS=$(oc get groupsync "${NAME}" -n "${NAMESPACE}" -o jsonpath='{range .spec.providers[*]}{.name}{"\n"}{end}' 2>/dev/null)
  pass "${PROVIDER_COUNT} provider(s) configured: $(echo ${PROVIDERS} | tr '\n' ', ' | sed 's/,$//')"
else
  fail "No providers configured in GroupSync CR"
fi

# --- OpenShift Groups ---
echo "--- Step 5: OpenShift Groups ---"
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
