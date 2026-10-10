#!/bin/bash
set -uo pipefail

# openshift-marketplace E2E Test
# Validates CatalogSource resources exist, their pods are running, and
# PackageManifests are queryable.
#
# Usage: ./e2e-test.sh [certified-name] [community-name]
# Example: ./e2e-test.sh local-certified-operators local-community-operators

CERTIFIED="${1:-local-certified-operators}"
COMMUNITY="${2:-local-community-operators}"
NAMESPACE="openshift-marketplace"
PASSED=0
FAILED=0
TOTAL=4

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

echo "=== openshift-marketplace E2E Test ==="
echo "  Namespace:  ${NAMESPACE}"
echo "  Certified:  ${CERTIFIED}"
echo "  Community:  ${COMMUNITY}"
echo ""

echo "--- Step 1: CatalogSource resources exist ---"
CS_FOUND=0
for cs in "${CERTIFIED}" "${COMMUNITY}"; do
  if oc get catalogsource "${cs}" -n "${NAMESPACE}" &>/dev/null; then
    CS_FOUND=$((CS_FOUND + 1))
  fi
done
if [ "${CS_FOUND}" -ge 1 ]; then
  pass "${CS_FOUND} CatalogSource(s) found"
else
  fail "No CatalogSources found"
fi

echo "--- Step 2: CatalogSource pods running ---"
POD_COUNT=$(oc get pods -n "${NAMESPACE}" -l "olm.catalogSource in (${CERTIFIED},${COMMUNITY})" \
  --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${POD_COUNT}" -ge 1 ]; then
  pass "${POD_COUNT} CatalogSource pod(s) running"
else
  fail "No CatalogSource pods running"
fi

echo "--- Step 3: CatalogSource connection state ---"
READY=0
for cs in "${CERTIFIED}" "${COMMUNITY}"; do
  STATE=$(oc get catalogsource "${cs}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null)
  if [ "${STATE}" = "READY" ]; then
    READY=$((READY + 1))
  fi
done
if [ "${READY}" -ge 1 ]; then
  pass "${READY} CatalogSource(s) in READY state"
else
  fail "No CatalogSources in READY state"
fi

echo "--- Step 4: PackageManifests queryable ---"
PKG_COUNT=$(oc get packagemanifests --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${PKG_COUNT}" -ge 1 ]; then
  pass "${PKG_COUNT} PackageManifests available"
else
  fail "No PackageManifests found"
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
