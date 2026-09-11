#!/bin/bash
set -euo pipefail

# etcd-defrag E2E Test
# Validates CronJob configuration, last Job status, and PrometheusRule alerts.
#
# Usage: ./e2e-test.sh [namespace]
# Example: ./e2e-test.sh openshift-etcd

NAMESPACE="${1:-openshift-etcd}"
PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }

echo "=== etcd-defrag E2E Test ==="
echo "  Namespace: ${NAMESPACE}"
echo ""

echo "--- Step 1: CronJob exists ---"
if oc get cronjob etcd-defrag -n "${NAMESPACE}" &>/dev/null; then
  pass "CronJob etcd-defrag exists"
else
  fail "CronJob etcd-defrag not found"
fi

echo "--- Step 2: CronJob schedule valid ---"
SCHEDULE=$(oc get cronjob etcd-defrag -n "${NAMESPACE}" -o jsonpath='{.spec.schedule}' 2>/dev/null)
if [ -n "${SCHEDULE}" ]; then
  pass "CronJob schedule is '${SCHEDULE}'"
else
  fail "CronJob has no schedule"
fi

echo "--- Step 3: ServiceAccount and RBAC ---"
if oc get serviceaccount etcd-defrag -n "${NAMESPACE}" &>/dev/null && \
   oc get clusterrolebinding etcd-defrag &>/dev/null; then
  pass "ServiceAccount and ClusterRoleBinding exist"
else
  fail "ServiceAccount or ClusterRoleBinding missing"
fi

echo "--- Step 4: Last Job status ---"
LAST_JOB=$(oc get jobs -n "${NAMESPACE}" --sort-by=.metadata.creationTimestamp \
  -l "batch.kubernetes.io/controller-uid" -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null | grep etcd-defrag || true)
if [ -n "${LAST_JOB}" ]; then
  STATUS=$(oc get job "${LAST_JOB}" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
  if [ "${STATUS}" = "Complete" ]; then
    pass "Last job ${LAST_JOB} completed successfully"
  else
    fail "Last job ${LAST_JOB} status: ${STATUS:-unknown}"
  fi
else
  fail "No etcd-defrag jobs found (CronJob may not have triggered yet)"
fi

echo "--- Step 5: PrometheusRule alerts ---"
if oc get prometheusrule etcd-defrag-alerts -n "${NAMESPACE}" &>/dev/null; then
  ALERT_COUNT=$(oc get prometheusrule etcd-defrag-alerts -n "${NAMESPACE}" \
    -o jsonpath='{.spec.groups[0].rules}' 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
  if [ "${ALERT_COUNT}" -ge 3 ]; then
    pass "PrometheusRule has ${ALERT_COUNT} alerts configured"
  else
    fail "Expected 3+ alerts, found ${ALERT_COUNT}"
  fi
else
  fail "PrometheusRule etcd-defrag-alerts not found"
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
