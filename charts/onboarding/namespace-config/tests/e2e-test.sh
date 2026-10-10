#!/bin/bash
set -uo pipefail

# namespace-config E2E Test
# Validates team namespaces are created with the right labels and RBAC, carry
# the default-deny NetworkPolicy, and that any ResourceQuota or LimitRange
# present matches the namespace's size tier.
#
# It reads the cluster, not the values chain, so it cannot see which objects a
# namespace is meant to have -- see the note on the quota check below.
#
# Usage: ./e2e-test.sh <team-name> <environment>
# Example: ./e2e-test.sh team-alpha dev

TEAM="${1:?Usage: $0 <team-name> <environment>}"
ENV="${2:?Usage: $0 <team-name> <environment>}"
PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

echo "=== namespace-config E2E Test ==="
echo "  Team:        ${TEAM}"
echo "  Environment: ${ENV}"
echo ""

NAMESPACES=$(oc get namespaces -l "argocd.argoproj.io/managed-by=${TEAM}-gitops" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

if [ -z "${NAMESPACES}" ]; then
  echo "  FAIL: No namespaces found with label argocd.argoproj.io/managed-by=${TEAM}-gitops"
  echo ""
  echo "=== Results ==="
  echo "  0/0 passed, 1 failed"
  echo "  E2E TEST FAILED"
  exit 1
fi

while IFS= read -r ns; do
  [ -z "${ns}" ] && continue
  echo "--- Namespace: ${ns} ---"

  TOTAL=$((TOTAL + 1))
  echo "  Checking namespace exists..."
  if oc get namespace "${ns}" &>/dev/null; then
    pass "Namespace ${ns} exists"
  else
    fail "Namespace ${ns} not found"
    continue
  fi

  TOTAL=$((TOTAL + 1))
  SIZE=$(oc get namespace "${ns}" -o jsonpath='{.metadata.labels.namespace-size}' 2>/dev/null)
  if [ -n "${SIZE}" ]; then
    pass "namespace-size label is '${SIZE}'"
  else
    fail "namespace-size label missing on ${ns}"
  fi

  # Both objects are switchable per tier and per namespace, so their absence is
  # ambiguous from the cluster alone: it is either a namespace deliberately not
  # enforced yet during a migration, or a sync that did not happen. This script
  # cannot tell -- it reads the cluster, not the values chain. It reports the
  # absence and leaves it, rather than failing every un-migrated namespace and
  # training everyone to ignore a red run.
  #
  # `scripts/render.sh <env>/<cluster> namespace-config --team <team>` is what
  # says which of the two it is, and `make validate-onboarding` renders every
  # pair. What IS checked below is that an object which exists matches its tier.
  if oc get resourcequota team-quota -n "${ns}" &>/dev/null; then
    TOTAL=$((TOTAL + 1))
    RQ_SIZE=$(oc get resourcequota team-quota -n "${ns}" -o jsonpath='{.metadata.labels.namespace-size}' 2>/dev/null)
    if [ "${RQ_SIZE}" = "${SIZE}" ]; then
      pass "ResourceQuota team-quota matches size '${SIZE}'"
    else
      fail "ResourceQuota size label '${RQ_SIZE}' does not match namespace size '${SIZE}'"
    fi
  else
    echo "  SKIP: no team-quota in ${ns} (resourceQuota switched off, or not synced?)"
  fi

  if oc get limitrange team-limits -n "${ns}" &>/dev/null; then
    TOTAL=$((TOTAL + 1))
    LR_SIZE=$(oc get limitrange team-limits -n "${ns}" -o jsonpath='{.metadata.labels.namespace-size}' 2>/dev/null)
    if [ "${LR_SIZE}" = "${SIZE}" ]; then
      pass "LimitRange team-limits matches size '${SIZE}'"
    else
      fail "LimitRange size label '${LR_SIZE}' does not match namespace size '${SIZE}'"
    fi
  else
    echo "  SKIP: no team-limits in ${ns} (limitRange switched off, or not synced?)"
  fi

  # default-deny-ingress is checked on its own rather than counting policies:
  # without it the other four are decoration, since they only add exceptions to
  # a deny that would not exist.
  TOTAL=$((TOTAL + 1))
  if oc get networkpolicy default-deny-ingress -n "${ns}" &>/dev/null; then
    pass "default-deny-ingress NetworkPolicy present"
  else
    fail "default-deny-ingress NetworkPolicy not found in ${ns} — the namespace is open"
  fi

  TOTAL=$((TOTAL + 1))
  if oc get rolebinding "${TEAM}-admin" -n "${ns}" &>/dev/null; then
    pass "RoleBinding ${TEAM}-admin present"
  else
    fail "RoleBinding ${TEAM}-admin not found in ${ns} — the team cannot reach its own namespace"
  fi

  # team.readers is optional, so its absence is reported but not failed.
  if oc get rolebinding "${TEAM}-view" -n "${ns}" &>/dev/null; then
    TOTAL=$((TOTAL + 1))
    pass "RoleBinding ${TEAM}-view present"
  else
    echo "  SKIP: no ${TEAM}-view RoleBinding (team.readers is unset?)"
  fi
  echo ""
done <<< "${NAMESPACES}"

echo "=== Results ==="
echo "  ${PASSED}/${TOTAL} passed, ${FAILED} failed"
if [ "${FAILED}" -eq 0 ]; then
  echo "  E2E TEST PASSED"
  exit 0
else
  echo "  E2E TEST FAILED"
  exit 1
fi
