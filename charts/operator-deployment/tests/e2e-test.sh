#!/bin/bash
set -uo pipefail

# Operator Deployment E2E Test
# Verifies all Subscriptions have a CSV in Succeeded phase.
#
# Usage: ./e2e-test.sh

PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

echo "=== Operator Deployment E2E Test ==="
echo ""

SUBS=$(oc get subscriptions.operators.coreos.com --all-namespaces --no-headers 2>/dev/null)
if [ -z "$SUBS" ]; then
  echo "  No Subscriptions found"
  exit 1
fi

while IFS= read -r line; do
  [ -z "$line" ] && continue
  NS=$(echo "$line" | awk '{print $1}')
  NAME=$(echo "$line" | awk '{print $2}')
  TOTAL=$((TOTAL + 1))

  echo "--- $NAME ($NS) ---"

  CSV=$(oc get subscription.operators.coreos.com "$NAME" -n "$NS" -o jsonpath='{.status.currentCSV}' 2>/dev/null || echo "")
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
done <<< "$SUBS"

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
