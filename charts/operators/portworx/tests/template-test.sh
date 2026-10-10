#!/bin/bash
set -uo pipefail

# Helm Template Tests for the portworx chart
# Covers the install block, the StorageCluster, and the px-pure-secret
# sources and guards.
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
  helm template portworx "$CHART_DIR" "$@" 2>&1
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

cat > "$TMPDIR/full.yaml" <<'EOF'
portworx:
  storageCluster:
    include: true
    name: px-cluster-test
    installSource: "https://install.portworx.com/26.2?oem=px-csi"
    pure:
      sanType: ISCSI
      iscsiAllowedCIDR: 10.0.0.0/24
    env:
      - name: PX_EXTRA
        value: somevalue
  pureSecret:
    include: true
    source: externalSecret
    flashArrays:
      - endpoint: 10.0.0.10
        tokenKey: api-token-array-1
    externalSecret:
      path: secret/data/portworx/flasharray
EOF

# ============================================================================
# Install block
# ============================================================================
echo "=== Install block ==="

OUTPUT=$(render)

for kind in Namespace OperatorGroup Subscription; do
  [ "$(count_kind "$OUTPUT" "$kind")" -eq 1 ] \
    && pass "$kind rendered by default" || fail "$kind missing"
done

has_string "$OUTPUT" "name: portworx-certified" \
  && pass "Subscription uses the portworx-certified package" || fail "wrong package"

has_string "$OUTPUT" "channel: stable" \
  && pass "default channel is stable" || fail "default channel wrong"

has_string "$OUTPUT" "source: certified-operators" \
  && pass "source is certified-operators" || fail "wrong catalogue source"

has_string "$OUTPUT" 'argocd.argoproj.io/sync-wave: "-28"' \
  && pass "Subscription at wave -28" || fail "Subscription wave wrong"

# AllNamespaces is supported, so the OperatorGroup carries no targetNamespaces.
has_string "$OUTPUT" "spec: {}" \
  && pass "cluster-scoped OperatorGroup" || fail "OperatorGroup not cluster-scoped"

OUTPUT=$(render --set installOperators=false)
if [ "$(count_kind "$OUTPUT" Subscription)" -eq 0 ]; then
  pass "installOperators=false drops the Subscription"
else
  fail "Subscription rendered with installOperators=false"
fi

# ============================================================================
# CR gating
# ============================================================================
echo "=== CR gating ==="

OUTPUT=$(render)
[ "$(count_kind "$OUTPUT" StorageCluster)" -eq 0 ] \
  && pass "no StorageCluster by default" || fail "StorageCluster rendered by default"
[ "$(count_kind "$OUTPUT" ExternalSecret)" -eq 0 ] \
  && pass "no ExternalSecret by default" || fail "ExternalSecret rendered by default"

# ============================================================================
# StorageCluster
# ============================================================================
echo "=== StorageCluster ==="

OUTPUT=$(render -f "$TMPDIR/full.yaml")

[ "$(count_kind "$OUTPUT" StorageCluster)" -eq 1 ] \
  && pass "StorageCluster rendered when included" || fail "StorageCluster missing"

has_string "$OUTPUT" "apiVersion: core.libopenstorage.org/v1" \
  && pass "StorageCluster apiVersion" || fail "wrong apiVersion"

has_string "$OUTPUT" 'portworx.io/is-openshift: "true"' \
  && pass "OpenShift annotation present" || fail "OpenShift annotation missing"

has_string "$OUTPUT" "namespace: portworx" \
  && pass "CR lands in the operator namespace" || fail "CR namespace wrong"

has_string "$OUTPUT" "name: px-cluster-test" \
  && pass "cluster name from values" || fail "cluster name wrong"

# --oem px-csi is the whole product selector. Without it this same CRD
# installs Portworx Enterprise.
has_string "$OUTPUT" 'portworx.io/misc-args: "--oem px-csi"' \
  && pass "misc-args carries --oem px-csi" || fail "--oem px-csi missing"

has_string "$OUTPUT" "portworx.io/install-source:" \
  && pass "install-source annotation present" || fail "install-source missing"

has_string "$OUTPUT" "image: portworx/px-pure-csi-driver:26.2.1" \
  && pass "PX-CSI driver image" || fail "wrong image"

has_string "$OUTPUT" 'value: "ISCSI"' \
  && pass "PURE_FLASHARRAY_SAN_TYPE from pure.sanType" || fail "sanType missing"

has_string "$OUTPUT" "PURE_ISCSI_ALLOWED_CIDR" \
  && pass "PURE_ISCSI_ALLOWED_CIDR from pure.iscsiAllowedCIDR" || fail "CIDR missing"

has_string "$OUTPUT" "PX_EXTRA" \
  && pass "free-form env appended" || fail "free-form env missing"

has_string "$OUTPUT" "exportMetrics: true" \
  && pass "exportMetrics on by default" || fail "exportMetrics missing"

# Enterprise-only fields must not appear: this chart is PX-CSI.
for field in kvdb cloudStorage secretsProvider stork autopilot; do
  if has_string "$OUTPUT" "  $field:"; then
    fail "Enterprise-only field $field rendered"
  else
    pass "no Enterprise-only $field"
  fi
done

# exportMetrics publishes to an existing Prometheus; enabled deploys one.
# They must stay separate knobs.
OUTPUT_PROM=$(render -f "$TMPDIR/full.yaml" --set portworx.storageCluster.monitoring.prometheusEnabled=true)
echo "$OUTPUT_PROM" | grep -A3 "prometheus:" | grep -q "enabled: true" \
  && pass "prometheusEnabled deploys a Prometheus" || fail "prometheusEnabled had no effect"

if echo "$OUTPUT" | grep -A3 "prometheus:" | grep -q "enabled: true"; then
  fail "Prometheus deployed without prometheusEnabled"
else
  pass "exportMetrics alone does not deploy a Prometheus"
fi

OUTPUT=$(render -f "$TMPDIR/full.yaml" --set portworx.storageCluster.isOpenShift=false)
if has_string "$OUTPUT" "portworx.io/is-openshift"; then
  fail "OpenShift annotation present when isOpenShift is false"
else
  pass "OpenShift annotation omitted when isOpenShift is false"
fi

# ============================================================================
# px-pure-secret
# ============================================================================
echo "=== px-pure-secret ==="

OUTPUT=$(render -f "$TMPDIR/full.yaml")

[ "$(count_kind "$OUTPUT" ExternalSecret)" -eq 1 ] \
  && pass "ExternalSecret rendered for source=externalSecret" || fail "ExternalSecret missing"

has_string "$OUTPUT" "name: px-pure-secret" \
  && pass "secret named px-pure-secret" || fail "secret name wrong"

has_string "$OUTPUT" 'argocd.argoproj.io/sync-wave: "-1"' \
  && pass "secret ahead of the StorageCluster at wave -1" || fail "secret wave wrong"

has_string "$OUTPUT" "engineVersion: v2" \
  && pass "ESO template engine v2" || fail "engineVersion missing"

# The token must be an index action, not dot notation: a hyphenated key is a
# Go template parse error as .api-token-array-1, and toJson must not have
# escaped the action's quotes.
has_string "$OUTPUT" '{{ index . "api-token-array-1" }}' \
  && pass "token placeholder uses unescaped index syntax" \
  || fail "token placeholder malformed — check the __PXTOKEN__ sentinel swap"

if has_string "$OUTPUT" '\"api-token-array-1\"'; then
  fail "toJson escaped the ESO action quotes"
else
  pass "no backslash-escaped quotes in the ESO action"
fi

has_string "$OUTPUT" '"MgmtEndPoint":"10.0.0.10"' \
  && pass "array endpoint in pure.json" || fail "array endpoint missing"

has_string "$OUTPUT" "property: api-token-array-1" \
  && pass "remoteRef property set from tokenKey" || fail "remoteRef property missing"

OUTPUT=$(render -f "$TMPDIR/full.yaml" --set portworx.pureSecret.source=existing)
if [ "$(count_kind "$OUTPUT" ExternalSecret)" -eq 0 ]; then
  pass "source=existing renders no secret"
else
  fail "ExternalSecret rendered for source=existing"
fi

# ============================================================================
# Guards
# ============================================================================
echo "=== Guards ==="

OUTPUT=$(render -f "$TMPDIR/full.yaml" --set portworx.pureSecret.source=bogus)
has_string "$OUTPUT" "expected existing or externalSecret" \
  && pass "unknown source fails the render" || fail "unknown source not caught"

OUTPUT=$(render --set portworx.pureSecret.include=true)
has_string "$OUTPUT" "neither flashArrays nor flashBlades" \
  && pass "no backend fails the render" || fail "empty backend list not caught"

OUTPUT=$(render -f "$TMPDIR/full.yaml" --set portworx.pureSecret.externalSecret.path="")
has_string "$OUTPUT" "externalSecret.path is required" \
  && pass "missing Vault path fails the render" || fail "missing Vault path not caught"

OUTPUT=$(render --set portworx.operator.channel="")
has_string "$OUTPUT" "operator.channel is required" \
  && pass "empty channel fails the render" || fail "empty channel not caught"

# The cluster name is the Portworx cluster ID, not cosmetic — it has no
# usable default, so an unset one must stop the render rather than ship.
OUTPUT=$(render --set portworx.storageCluster.include=true)
has_string "$OUTPUT" "storageCluster.name is required" \
  && pass "missing cluster name fails the render" || fail "missing cluster name not caught"

OUTPUT=$(render -f "$TMPDIR/full.yaml" --set portworx.storageCluster.image="")
has_string "$OUTPUT" "storageCluster.image is required" \
  && pass "empty image fails the render" || fail "empty image not caught"

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
