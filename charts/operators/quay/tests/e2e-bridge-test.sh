#!/bin/bash
set -euo pipefail

# Quay Bridge E2E Test
# Tests the full lifecycle: namespace -> Quay org -> build -> push -> pull -> cleanup
#
# Usage: ./e2e-bridge-test.sh <quay-hostname> <oauth-token>
# Example: ./e2e-bridge-test.sh registry-quay-quay-enterprise.apps.cluster-xyz.example.com CHANGEME_QUAY_BRIDGE_OAUTH_TOKEN

QUAY_HOST="${1:?Usage: $0 <quay-hostname> <oauth-token>}"
OAUTH_TOKEN="${2:?Usage: $0 <quay-hostname> <oauth-token>}"
NAMESPACE="quay-e2e-test-$(date +%s | tail -c 6)"
QUAY_ORG="openshift_${NAMESPACE}"
PASSED=0
FAILED=0
TOTAL=6

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }

cleanup() {
  echo ""
  echo "=== Cleanup ==="
  oc delete namespace "${NAMESPACE}" --wait=false 2>/dev/null && echo "  Namespace ${NAMESPACE} deletion initiated" || true
}
trap cleanup EXIT

echo "=== Quay Bridge E2E Test ==="
echo "  Namespace:  ${NAMESPACE}"
echo "  Quay Host:  ${QUAY_HOST}"
echo "  Quay Org:   ${QUAY_ORG}"
echo ""

# 1. Create namespace with bridge opt-in
echo "--- Step 1: Create namespace ---"
oc create namespace "${NAMESPACE}"
oc label namespace "${NAMESPACE}" openshift.io/quay-bridge-operator=true
pass "Namespace created"

# 2. Wait for bridge to create Quay org and provision secrets
echo "--- Step 2: Wait for bridge sync ---"
for i in $(seq 1 30); do
  ORG_STATUS=$(curl -s -k -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${OAUTH_TOKEN}" \
    "https://${QUAY_HOST}/api/v1/organization/${QUAY_ORG}")
  if [ "${ORG_STATUS}" = "200" ]; then
    break
  fi
  sleep 5
done
if [ "${ORG_STATUS}" = "200" ]; then
  pass "Quay org ${QUAY_ORG} created"
else
  fail "Quay org not created (HTTP ${ORG_STATUS})"
fi

# Check secrets
SECRET_COUNT=$(oc get secrets -n "${NAMESPACE}" --no-headers 2>/dev/null | grep -c 'quay-openshift' || true)
if [ "${SECRET_COUNT}" -ge 3 ]; then
  pass "Quay dockerconfigjson secrets provisioned (${SECRET_COUNT} SAs)"
else
  fail "Expected 3+ quay secrets, found ${SECRET_COUNT}"
fi

# 3. Build image
echo "--- Step 3: Build image ---"
oc new-build --name=test-app \
  --dockerfile='FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
RUN echo "Quay Bridge E2E Test" > /tmp/index.html
CMD ["cat", "/tmp/index.html"]' \
  -n "${NAMESPACE}"

oc wait --for=condition=complete "build/test-app-1" -n "${NAMESPACE}" --timeout=300s
pass "Image built"

# 4. Verify image in Quay
echo "--- Step 4: Verify image in Quay ---"
sleep 5
REPO_STATUS=$(curl -s -k -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${OAUTH_TOKEN}" \
  "https://${QUAY_HOST}/api/v1/repository/${QUAY_ORG}/test-app")
if [ "${REPO_STATUS}" = "200" ]; then
  pass "Image synced to Quay repo ${QUAY_ORG}/test-app"
else
  fail "Image not found in Quay (HTTP ${REPO_STATUS})"
fi

# 5. Pull image from Quay
echo "--- Step 5: Pull image from Quay ---"
oc create deployment test-pull \
  --image="${QUAY_HOST}/${QUAY_ORG}/test-app:latest" \
  -n "${NAMESPACE}"

oc wait --for=jsonpath='{.status.readyReplicas}'=1 deployment/test-pull \
  -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true

POD_IMAGE=$(oc get pod -n "${NAMESPACE}" -l app=test-pull \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}' 2>/dev/null)
if echo "${POD_IMAGE}" | grep -q "${QUAY_HOST}"; then
  pass "Image pulled from Quay"
else
  fail "Image pull from Quay could not be verified"
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
