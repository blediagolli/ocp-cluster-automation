#!/bin/bash
set -euo pipefail

# Operator Deployment E2E Test
# Verifies all Subscriptions have a CSV in Succeeded phase.
#
# Usage: ./e2e-test.sh

PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }

echo "=== Operator Deployment E2E Test ==="
echo ""

SUBS=$(oc get subscriptions.operators.coreos.com --all-namespaces -o json)
SUB_COUNT=$(echo "$SUBS" | jq '.items | length')

if [ "$SUB_COUNT" -eq 0 ]; then
  echo "  No Subscriptions found"
  exit 1
fi

for i in $(seq 0 $((SUB_COUNT - 1))); do
  NAME=$(echo "$SUBS" | jq -r ".items[$i].metadata.name")
  NS=$(echo "$SUBS" | jq -r ".items[$i].metadata.namespace")
  CSV=$(echo "$SUBS" | jq -r ".items[$i].status.currentCSV // empty")
  ((TOTAL++))

  echo "--- $NAME ($NS) ---"

  if [ -z "$CSV" ]; then
    fail "$NAME has no currentCSV"
    continue
  fi

  PHASE=$(oc get csv "$CSV" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
  if [ "$PHASE" = "Succeeded" ]; then
    pass "$CSV phase=Succeeded"
  else
    fail "$CSV phase=$PHASE (expected Succeeded)"
  fi
done

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
