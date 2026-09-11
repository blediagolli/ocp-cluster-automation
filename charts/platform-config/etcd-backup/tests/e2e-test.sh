#!/bin/bash
set -euo pipefail

# etcd Backup E2E Test
# Validates CronJob, last Job status, storage binding, and backup content
#
# Usage: ./e2e-test.sh [namespace]
# Example: ./e2e-test.sh openshift-etcd

NAMESPACE="${1:-openshift-etcd}"
PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }

echo "=== etcd Backup E2E Test ==="
echo "  Namespace: ${NAMESPACE}"
echo ""

# 1. Check CronJob exists
echo "--- Step 1: CronJob ---"
CJ_SCHEDULE=$(oc get cronjob etcd-backup -n "${NAMESPACE}" -o jsonpath='{.spec.schedule}' 2>/dev/null || echo "")
if [ -n "${CJ_SCHEDULE}" ]; then
  LAST_SCHEDULE=$(oc get cronjob etcd-backup -n "${NAMESPACE}" -o jsonpath='{.status.lastScheduleTime}' 2>/dev/null || echo "never")
  pass "CronJob schedule: ${CJ_SCHEDULE} (last: ${LAST_SCHEDULE})"
else
  fail "CronJob etcd-backup not found"
fi

# 2. Check last Job status
echo "--- Step 2: Last Job status ---"
LAST_JOB=$(oc get jobs -n "${NAMESPACE}" -l app=etcd-backup --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")
if [ -n "${LAST_JOB}" ]; then
  JOB_STATUS=$(oc get job "${LAST_JOB}" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
  if [ "${JOB_STATUS}" = "Complete" ]; then
    pass "Last job ${LAST_JOB}: ${JOB_STATUS}"
  else
    fail "Last job ${LAST_JOB}: ${JOB_STATUS}"
  fi
else
  fail "No backup jobs found (CronJob may not have run yet)"
fi

# 3. Check ServiceAccount and RBAC
echo "--- Step 3: ServiceAccount and RBAC ---"
SA=$(oc get serviceaccount etcd-backup -n "${NAMESPACE}" -o name 2>/dev/null || echo "")
CRB=$(oc get clusterrolebinding etcd-backup -o name 2>/dev/null || echo "")
if [ -n "${SA}" ] && [ -n "${CRB}" ]; then
  pass "ServiceAccount and ClusterRoleBinding exist"
else
  fail "ServiceAccount (${SA:-missing}) or ClusterRoleBinding (${CRB:-missing})"
fi

# 4. Check storage
echo "--- Step 4: Storage ---"
PVC=$(oc get pvc -n "${NAMESPACE}" --no-headers 2>/dev/null | grep "etcd-backup" || true)
OBC=$(oc get objectbucketclaim -n "${NAMESPACE}" --no-headers 2>/dev/null | grep "etcd-backup" || true)
if [ -n "${PVC}" ]; then
  PVC_STATUS=$(echo "${PVC}" | awk '{print $2}')
  if [ "${PVC_STATUS}" = "Bound" ]; then
    pass "PVC storage: Bound"
  else
    fail "PVC storage: ${PVC_STATUS}"
  fi
elif [ -n "${OBC}" ]; then
  OBC_STATUS=$(echo "${OBC}" | awk '{print $2}')
  if [ "${OBC_STATUS}" = "Bound" ]; then
    pass "OBC storage: Bound"
  else
    fail "OBC storage: ${OBC_STATUS}"
  fi
else
  fail "No PVC or OBC found for etcd-backup"
fi

# 5. Check backup script ConfigMap
echo "--- Step 5: Backup script ConfigMap ---"
CM=$(oc get configmap etcd-backup-script -n "${NAMESPACE}" -o name 2>/dev/null || echo "")
if [ -n "${CM}" ]; then
  KEYS=$(oc get configmap etcd-backup-script -n "${NAMESPACE}" -o jsonpath='{.data}' 2>/dev/null | grep -c "backup.sh" || true)
  if [ "${KEYS}" -ge 1 ]; then
    pass "Backup script ConfigMap with backup.sh"
  else
    fail "Backup script ConfigMap missing backup.sh key"
  fi
else
  fail "Backup script ConfigMap not found"
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
