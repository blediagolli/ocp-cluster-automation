#!/bin/bash
set -uo pipefail

# Helm Template Tests for pure-storage-node-config chart
# Validates the Pure Storage MachineConfig: include gate, per-role rendering,
# decoded multipath.conf / udev rules content, and systemd units.
#
# Usage: ./template-test.sh
# Requirements: helm 3.x, base64

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); TOTAL=$((TOTAL + 1)); }

render() {
  helm template test-pure-storage "$CHART_DIR" --values "$1" 2>&1
}

has_string() {
  echo "$1" | grep -qF "$2"
}

count_kind() {
  local n
  n=$(echo "$1" | grep -c "^kind: $2") || true
  echo "$n"
}

# Decode the embedded file whose path follows the data URL ($2 = target path)
decode_file() {
  echo "$1" | awk -v p="path: $2" '
    /base64,/ { sub(/.*base64,/, ""); b = $0 }
    index($0, p) { print b; exit }' | base64 -d 2>/dev/null
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
pureStorage:
  include: false
EOF

cat > "$TMPDIR/defaults.yaml" <<'EOF'
pureStorage:
  include: true
EOF

cat > "$TMPDIR/custom.yaml" <<'EOF'
pureStorage:
  include: true
  roles:
    - worker
    - master
  enableIscsid: false
  multipath:
    pollingInterval: 5
    findMultipaths: "no"
    detectPrioNo: true
    extraBlacklistDevnodes:
      - "^sda$"
EOF

# ============================================================================
# Tests: include gate
# ============================================================================
echo "=== Include gate ==="

OUTPUT=$(render "$TMPDIR/disabled.yaml")
if [ "$(count_kind "$OUTPUT" MachineConfig)" -eq 0 ]; then
  pass "no MachineConfig when include is false"
else
  fail "MachineConfig rendered when include is false"
fi

# ============================================================================
# Tests: defaults
# ============================================================================
echo "=== Defaults ==="

OUTPUT=$(render "$TMPDIR/defaults.yaml")

if [ "$(count_kind "$OUTPUT" MachineConfig)" -eq 1 ]; then
  pass "one MachineConfig for default roles"
else
  fail "expected 1 MachineConfig, got $(count_kind "$OUTPUT" MachineConfig)"
fi

has_string "$OUTPUT" "name: 99-worker-pure-storage" \
  && pass "MachineConfig named 99-worker-pure-storage" \
  || fail "MachineConfig name wrong"

has_string "$OUTPUT" "machineconfiguration.openshift.io/role: worker" \
  && pass "worker role label" || fail "worker role label missing"

has_string "$OUTPUT" "path: /etc/multipath.conf" \
  && pass "multipath.conf file present" || fail "multipath.conf file missing"

has_string "$OUTPUT" "path: /etc/udev/rules.d/99-pure-storage.rules" \
  && pass "udev rules file present" || fail "udev rules file missing"

has_string "$OUTPUT" "mode: 420" \
  && pass "file mode is decimal 420" || fail "file mode not 420"

has_string "$OUTPUT" "name: multipathd.service" \
  && pass "multipathd.service enabled" || fail "multipathd.service missing"

has_string "$OUTPUT" "name: iscsid.service" \
  && pass "iscsid.service enabled by default" || fail "iscsid.service missing"

MPCONF=$(decode_file "$OUTPUT" /etc/multipath.conf)

has_string "$MPCONF" 'devnode "^pxd[0-9]*"' \
  && pass "multipath.conf blacklists pxd devices" || fail "pxd blacklist missing"

has_string "$MPCONF" 'product "Virtual disk"' \
  && pass "multipath.conf blacklists VMware virtual disks" || fail "VMware blacklist missing"

has_string "$MPCONF" "polling_interval 10" \
  && pass "polling_interval 10" || fail "polling_interval not 10"

has_string "$MPCONF" "find_multipaths yes" \
  && pass "find_multipaths yes" || fail "find_multipaths not yes"

has_string "$MPCONF" 'product "Pure Storage FlashArray"' \
  && pass "NVMe device stanza present" || fail "NVMe device stanza missing"

has_string "$MPCONF" 'product "FlashArray"' \
  && pass "SCSI device stanza present" || fail "SCSI device stanza missing"

has_string "$MPCONF" 'hardware_handler "1 alua"' \
  && pass "SCSI stanza uses ALUA" || fail "ALUA hardware handler missing"

has_string "$MPCONF" "dev_loss_tmo 600" \
  && pass "SCSI dev_loss_tmo 600" || fail "SCSI dev_loss_tmo wrong"

if has_string "$MPCONF" "detect_prio"; then
  fail "detect_prio present when detectPrioNo is false"
else
  pass "detect_prio absent by default"
fi

UDEV=$(decode_file "$OUTPUT" /etc/udev/rules.d/99-pure-storage.rules)

UDEV_RULES=$(echo "$UDEV" | grep -c '^ACTION==') || true
if [ "$UDEV_RULES" -eq 4 ]; then
  pass "udev file has 4 rules"
else
  fail "udev file has $UDEV_RULES rules, expected 4"
fi

for attr in 'queue/scheduler}="none"' 'queue/add_random}="0"' 'queue/rq_affinity}="2"' 'device/timeout}="60"'; do
  has_string "$UDEV" "$attr" && pass "udev sets $attr" || fail "udev missing $attr"
done

# ============================================================================
# Tests: custom values
# ============================================================================
echo "=== Custom values ==="

OUTPUT=$(render "$TMPDIR/custom.yaml")

if [ "$(count_kind "$OUTPUT" MachineConfig)" -eq 2 ]; then
  pass "one MachineConfig per role"
else
  fail "expected 2 MachineConfigs, got $(count_kind "$OUTPUT" MachineConfig)"
fi

has_string "$OUTPUT" "name: 99-master-pure-storage" \
  && pass "master MachineConfig rendered" || fail "master MachineConfig missing"

has_string "$OUTPUT" "machineconfiguration.openshift.io/role: master" \
  && pass "master role label" || fail "master role label missing"

if has_string "$OUTPUT" "name: iscsid.service"; then
  fail "iscsid.service present when enableIscsid is false"
else
  pass "iscsid.service omitted when enableIscsid is false"
fi

has_string "$OUTPUT" "name: multipathd.service" \
  && pass "multipathd.service still enabled" || fail "multipathd.service missing"

MPCONF=$(decode_file "$OUTPUT" /etc/multipath.conf)

has_string "$MPCONF" 'detect_prio "no"' \
  && pass "detect_prio no when detectPrioNo is true" || fail "detect_prio missing"

has_string "$MPCONF" 'devnode "^sda$"' \
  && pass "extra blacklist devnode added" || fail "extra blacklist devnode missing"

has_string "$MPCONF" "polling_interval 5" \
  && pass "polling_interval override" || fail "polling_interval override missing"

has_string "$MPCONF" "find_multipaths no" \
  && pass "find_multipaths override" || fail "find_multipaths override missing"

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
