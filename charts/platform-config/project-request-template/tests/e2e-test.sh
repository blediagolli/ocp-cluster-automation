#!/bin/bash
set -euo pipefail

# project-request-template E2E Test
# Validates the Template exists, Project config references it, and creating a
# new project injects the configured resources (NetworkPolicy, ResourceQuota,
# LimitRange).
#
# Usage: ./e2e-test.sh
# Example: ./e2e-test.sh

NAMESPACE="openshift-config"
TEST_PROJECT="e2e-template-test-$(date +%s | tail -c 6)"
PASSED=0
FAILED=0
TOTAL=5

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }

cleanup() {
  echo ""
  echo "=== Cleanup ==="
  oc delete project "${TEST_PROJECT}" --wait=false 2>/dev/null && echo "  Project ${TEST_PROJECT} deletion initiated" || true
}
trap cleanup EXIT

echo "=== project-request-template E2E Test ==="
echo "  Namespace:    ${NAMESPACE}"
echo "  Test project: ${TEST_PROJECT}"
echo ""

echo "--- Step 1: Template exists ---"
if oc get template project-request -n "${NAMESPACE}" &>/dev/null; then
  OBJECT_COUNT=$(oc get template project-request -n "${NAMESPACE}" -o jsonpath='{.objects}' 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
  pass "Template project-request exists with ${OBJECT_COUNT} objects"
else
  fail "Template project-request not found in ${NAMESPACE}"
fi

echo "--- Step 2: Project config references template ---"
TEMPLATE_REF=$(oc get project.config.openshift.io cluster -o jsonpath='{.spec.projectRequestTemplate.name}' 2>/dev/null)
if [ "${TEMPLATE_REF}" = "project-request" ]; then
  pass "Project config references project-request template"
else
  fail "Project config template ref is '${TEMPLATE_REF}', expected 'project-request'"
fi

echo "--- Step 3: Create test project ---"
if oc new-project "${TEST_PROJECT}" --display-name="E2E Template Test" &>/dev/null; then
  pass "Project ${TEST_PROJECT} created"
else
  fail "Failed to create project ${TEST_PROJECT}"
fi

echo "--- Step 4: NetworkPolicy injected ---"
sleep 3
NP_COUNT=$(oc get networkpolicy -n "${TEST_PROJECT}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${NP_COUNT}" -ge 1 ]; then
  pass "NetworkPolicy injected (${NP_COUNT} policies)"
else
  fail "No NetworkPolicy found in ${TEST_PROJECT} (template may not include networkPolicy)"
fi

echo "--- Step 5: ResourceQuota and LimitRange ---"
RQ=$(oc get resourcequota -n "${TEST_PROJECT}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
LR=$(oc get limitrange -n "${TEST_PROJECT}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${RQ}" -ge 1 ] && [ "${LR}" -ge 1 ]; then
  pass "ResourceQuota (${RQ}) and LimitRange (${LR}) present"
else
  fail "ResourceQuota count=${RQ}, LimitRange count=${LR} (expected >=1 each, may not be configured in template)"
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
