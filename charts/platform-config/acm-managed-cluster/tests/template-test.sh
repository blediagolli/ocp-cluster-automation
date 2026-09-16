#!/bin/bash
set -uo pipefail

# Helm Template Tests for acm-managed-cluster chart
# Validates ManagedCluster rendering, import guards, PreSync check, and addons.
#
# Usage: ./template-test.sh
# Requirements: helm 3.x

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); TOTAL=$((TOTAL + 1)); }

render() {
  helm template test-import "$CHART_DIR" --values "$1" 2>&1
}

has_kind() {
  echo "$1" | grep -q "^kind: $2"
}

has_string() {
  echo "$1" | grep -qF "$2"
}

count_kind() {
  local n
  n=$(echo "$1" | grep -c "^kind: $2") || true
  echo "$n"
}

if ! command -v helm &>/dev/null; then
  echo "ERROR: helm not found in PATH"
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ============================================================================
# Test values files
# ============================================================================

cat > "$TMPDIR/disabled.yaml" <<'EOF'
cluster:
  name: test-cluster
  environment: dev
  address: "https://api.test.example.com:6443"
managedCluster:
  include: false
EOF

cat > "$TMPDIR/basic-import.yaml" <<'EOF'
cluster:
  name: test-cluster
  environment: dev
  address: "https://api.test.example.com:6443"
managedCluster:
  include: true
  vendor: OpenShift
  cloudProvider: Amazon
  clusterSet: default
  hubAcceptsClient: true
  addons:
    include: true
    config-policy-controller: true
    governance-policy-framework: true
    work-manager: true
    application-manager: true
    cert-policy-controller: true
    search-collector: true
    cluster-proxy: false
    managed-serviceaccount: false
EOF

cat > "$TMPDIR/import-with-provision.yaml" <<'EOF'
cluster:
  name: test-cluster
  environment: dev
  address: "https://api.test.example.com:6443"
deployProvision: true
managedCluster:
  include: true
  vendor: OpenShift
  clusterSet: default
  hubAcceptsClient: true
  addons:
    include: true
    config-policy-controller: true
    governance-policy-framework: true
    work-manager: true
    application-manager: false
    cert-policy-controller: false
    search-collector: false
    cluster-proxy: false
    managed-serviceaccount: false
EOF

cat > "$TMPDIR/import-no-provision.yaml" <<'EOF'
cluster:
  name: test-cluster
  environment: dev
  address: "https://api.test.example.com:6443"
deployProvision: false
managedCluster:
  include: true
  vendor: OpenShift
  clusterSet: default
  hubAcceptsClient: true
  addons:
    include: true
    config-policy-controller: true
    governance-policy-framework: true
    work-manager: true
    application-manager: false
    cert-policy-controller: false
    search-collector: false
    cluster-proxy: false
    managed-serviceaccount: false
EOF

cat > "$TMPDIR/import-with-auto-kubeconfig.yaml" <<'EOF'
cluster:
  name: test-cluster
  environment: dev
  address: "https://api.test.example.com:6443"
managedCluster:
  include: true
  registerArgoCD: false
  vendor: OpenShift
  clusterSet: default
  hubAcceptsClient: true
  autoImport:
    include: true
    mode: kubeconfig
    kubeconfig:
      secretName: test-cluster-admin-kubeconfig
    token:
      server: ""
      value: ""
  addons:
    include: true
    config-policy-controller: true
    governance-policy-framework: true
    work-manager: true
    application-manager: true
    cert-policy-controller: true
    search-collector: true
    cluster-proxy: false
    managed-serviceaccount: false
EOF

cat > "$TMPDIR/addons-disabled.yaml" <<'EOF'
cluster:
  name: test-cluster
  environment: dev
  address: "https://api.test.example.com:6443"
managedCluster:
  include: true
  vendor: OpenShift
  clusterSet: default
  hubAcceptsClient: true
  addons:
    include: false
    config-policy-controller: true
    governance-policy-framework: true
    work-manager: true
    application-manager: true
    cert-policy-controller: true
    search-collector: true
    cluster-proxy: false
    managed-serviceaccount: false
EOF

echo "=== Helm Template Tests: acm-managed-cluster ==="
echo ""

# ============================================================================
# Test 1: Disabled — renders nothing
# ============================================================================
echo "--- Test 1: managedCluster.include=false renders nothing ---"
OUTPUT=$(render "$TMPDIR/disabled.yaml")
if [ -z "$(echo "$OUTPUT" | grep -v '^$')" ]; then
  pass "No resources rendered when managedCluster.include=false"
else
  fail "Resources rendered when managedCluster.include=false"
fi

# ============================================================================
# Test 2: Basic import — ManagedCluster, addons, PreSync check
# ============================================================================
echo ""
echo "--- Test 2: Basic import (no deployProvision) ---"
OUTPUT=$(render "$TMPDIR/basic-import.yaml")

if [ $? -eq 0 ]; then
  pass "basic import renders successfully"
else
  fail "basic import render failed"
fi

if has_kind "$OUTPUT" "ManagedCluster"; then
  pass "ManagedCluster present"
else
  fail "ManagedCluster absent"
fi

if has_string "$OUTPUT" "name: test-cluster"; then
  pass "ManagedCluster name correct"
else
  fail "ManagedCluster name incorrect"
fi

if has_string "$OUTPUT" "vendor: OpenShift"; then
  pass "vendor label set"
else
  fail "vendor label missing"
fi

if has_string "$OUTPUT" "cloud: Amazon"; then
  pass "cloud label set"
else
  fail "cloud label missing"
fi

if has_string "$OUTPUT" "hubAcceptsClient: true"; then
  pass "hubAcceptsClient set"
else
  fail "hubAcceptsClient missing"
fi

if has_kind "$OUTPUT" "ManagedClusterAddOn"; then
  pass "ManagedClusterAddOns present"
else
  fail "ManagedClusterAddOns absent"
fi

ADDON_COUNT=$(count_kind "$OUTPUT" "ManagedClusterAddOn")
if [ "$ADDON_COUNT" -eq 6 ]; then
  pass "6 addons rendered (correct — 6 enabled, 2 disabled)"
else
  fail "expected 6 addons, got $ADDON_COUNT"
fi

if has_string "$OUTPUT" "name: config-policy-controller"; then
  pass "config-policy-controller addon present"
else
  fail "config-policy-controller addon missing"
fi

if has_string "$OUTPUT" "name: search-collector"; then
  pass "search-collector addon present"
else
  fail "search-collector addon missing"
fi

# PreSync check Job
if has_string "$OUTPUT" "test-cluster-import-check"; then
  pass "PreSync check Job present"
else
  fail "PreSync check Job absent"
fi

if has_kind "$OUTPUT" "ClusterRole"; then
  pass "PreSync ClusterRole present"
else
  fail "PreSync ClusterRole absent"
fi

if has_kind "$OUTPUT" "ClusterRoleBinding"; then
  pass "PreSync ClusterRoleBinding present"
else
  fail "PreSync ClusterRoleBinding absent"
fi

if has_string "$OUTPUT" "argocd.argoproj.io/hook: PreSync"; then
  pass "PreSync hook annotation present"
else
  fail "PreSync hook annotation missing"
fi

if has_string "$OUTPUT" "argocd.argoproj.io/hook-delete-policy: BeforeHookCreation"; then
  pass "BeforeHookCreation delete policy present"
else
  fail "BeforeHookCreation delete policy missing"
fi

if has_string "$OUTPUT" 'oc get managedcluster'; then
  pass "PreSync Job checks for existing ManagedCluster"
else
  fail "PreSync Job missing managedcluster check"
fi

if has_string "$OUTPUT" "managedclusters"; then
  pass "ClusterRole grants access to managedclusters"
else
  fail "ClusterRole missing managedclusters permission"
fi

# ============================================================================
# Test 3: Static guard — fail when deployProvision=true
# ============================================================================
echo ""
echo "--- Test 3: Static guard — deployProvision=true blocks import ---"
OUTPUT=$(render "$TMPDIR/import-with-provision.yaml" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  pass "template fails when deployProvision=true"
else
  fail "template should fail when deployProvision=true"
fi

if echo "$OUTPUT" | grep -qF "cluster-import is not needed for ACM-provisioned clusters"; then
  pass "error message is descriptive"
else
  fail "error message missing or unclear"
fi

# ============================================================================
# Test 4: deployProvision=false — renders normally
# ============================================================================
echo ""
echo "--- Test 4: deployProvision=false renders normally ---"
OUTPUT=$(render "$TMPDIR/import-no-provision.yaml")

if [ $? -eq 0 ]; then
  pass "renders when deployProvision=false"
else
  fail "render failed when deployProvision=false"
fi

if has_kind "$OUTPUT" "ManagedCluster"; then
  pass "ManagedCluster present with deployProvision=false"
else
  fail "ManagedCluster missing with deployProvision=false"
fi

ADDON_COUNT=$(count_kind "$OUTPUT" "ManagedClusterAddOn")
if [ "$ADDON_COUNT" -eq 3 ]; then
  pass "3 addons rendered (correct — 3 enabled)"
else
  fail "expected 3 addons, got $ADDON_COUNT"
fi

# ============================================================================
# Test 5: Auto-import kubeconfig mode
# ============================================================================
echo ""
echo "--- Test 5: Auto-import kubeconfig mode ---"
OUTPUT=$(render "$TMPDIR/import-with-auto-kubeconfig.yaml")

if [ $? -eq 0 ]; then
  pass "auto-import kubeconfig mode renders"
else
  fail "auto-import kubeconfig mode failed"
fi

if has_string "$OUTPUT" "test-cluster-auto-import"; then
  pass "auto-import Job present"
else
  fail "auto-import Job absent"
fi

if has_string "$OUTPUT" "test-cluster-admin-kubeconfig"; then
  pass "kubeconfig secret name referenced"
else
  fail "kubeconfig secret name missing"
fi

if has_string "$OUTPUT" "argocd.argoproj.io/hook: PostSync"; then
  pass "auto-import uses PostSync hook"
else
  fail "auto-import missing PostSync hook"
fi

# ============================================================================
# Test 6: Addons disabled
# ============================================================================
echo ""
echo "--- Test 6: Addons disabled ---"
OUTPUT=$(render "$TMPDIR/addons-disabled.yaml")

if [ $? -eq 0 ]; then
  pass "renders with addons disabled"
else
  fail "render failed with addons disabled"
fi

ADDON_COUNT=$(count_kind "$OUTPUT" "ManagedClusterAddOn")
if [ "$ADDON_COUNT" -eq 0 ]; then
  pass "no addons when addons.include=false"
else
  fail "expected 0 addons, got $ADDON_COUNT"
fi

if has_kind "$OUTPUT" "ManagedCluster"; then
  pass "ManagedCluster still present with addons disabled"
else
  fail "ManagedCluster missing with addons disabled"
fi

# ============================================================================
# Results
# ============================================================================
echo ""
echo "=== Results ==="
echo "  ${PASSED}/${TOTAL} passed, ${FAILED} failed"
if [ "${FAILED}" -eq 0 ]; then
  echo "  TEMPLATE TEST PASSED"
  exit 0
else
  echo "  TEMPLATE TEST FAILED"
  exit 1
fi
