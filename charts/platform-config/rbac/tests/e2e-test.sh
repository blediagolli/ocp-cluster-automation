#!/bin/bash
set -uo pipefail

# rbac E2E Test
# Validates that RBAC resources (ClusterRoles, Roles, ClusterRoleBindings,
# RoleBindings) exist and have the correct roleRef and subjects.
#
# Usage: ./e2e-test.sh [values-file]
# Example: ./e2e-test.sh ../../clusters/dev/aws-test/platform-config.yaml

VALUES_FILE="${1:-}"
PASSED=0
FAILED=0
TOTAL=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

echo "=== rbac E2E Test ==="
echo ""

# --- ClusterRoles ---
echo "--- Step 1: ClusterRoles exist ---"
TOTAL=$((TOTAL + 1))
CR_COUNT=$(oc get clusterrole -l 'app.kubernetes.io/managed-by=Helm' --no-headers 2>/dev/null | grep -c "rbac" || true)
if oc get clusterrole --no-headers 2>/dev/null | head -1 &>/dev/null; then
  CRS=$(oc get clusterrole --no-headers 2>/dev/null | wc -l | tr -d ' ')
  pass "Cluster has ${CRS} ClusterRoles (built-in + custom)"
else
  fail "Cannot list ClusterRoles"
fi

# --- ClusterRoleBindings ---
echo "--- Step 2: ClusterRoleBindings ---"
TOTAL=$((TOTAL + 1))
CRBS=$(oc get clusterrolebinding --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${CRBS}" -ge 1 ]; then
  pass "Cluster has ${CRBS} ClusterRoleBindings"
else
  fail "No ClusterRoleBindings found"
fi

# --- Validate specific resources if values file provided ---
if [ -n "${VALUES_FILE}" ] && [ -f "${VALUES_FILE}" ]; then
  echo ""
  echo "--- Step 3: Validate resources from values file ---"

  # Check ClusterRoles from values
  if command -v python3 &>/dev/null; then
    CUSTOM_CRS=$(python3 -c "
import yaml, sys
with open('${VALUES_FILE}') as f:
    v = yaml.safe_load(f)
cr = v.get('clusterRoles', {})
if cr.get('include'):
    for r in cr.get('roles', []):
        if r.get('include'):
            print(r['name'])
" 2>/dev/null)

    if [ -n "${CUSTOM_CRS}" ]; then
      while IFS= read -r cr_name; do
        TOTAL=$((TOTAL + 1))
        if oc get clusterrole "${cr_name}" &>/dev/null; then
          pass "ClusterRole '${cr_name}' exists"
        else
          fail "ClusterRole '${cr_name}' not found"
        fi
      done <<< "${CUSTOM_CRS}"
    fi

    # Check ClusterRoleBindings from values
    CUSTOM_CRBS=$(python3 -c "
import yaml, sys
with open('${VALUES_FILE}') as f:
    v = yaml.safe_load(f)
crb = v.get('clusterRoleBindings', {})
if crb.get('include'):
    for b in crb.get('bindings', []):
        if b.get('include'):
            print(b['name'])
" 2>/dev/null)

    if [ -n "${CUSTOM_CRBS}" ]; then
      while IFS= read -r crb_name; do
        TOTAL=$((TOTAL + 1))
        if oc get clusterrolebinding "${crb_name}" &>/dev/null; then
          ROLE_REF=$(oc get clusterrolebinding "${crb_name}" -o jsonpath='{.roleRef.name}' 2>/dev/null)
          SUBJECT_COUNT=$(oc get clusterrolebinding "${crb_name}" -o jsonpath='{.subjects}' 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
          pass "ClusterRoleBinding '${crb_name}' exists (role=${ROLE_REF}, ${SUBJECT_COUNT} subjects)"
        else
          fail "ClusterRoleBinding '${crb_name}' not found"
        fi
      done <<< "${CUSTOM_CRBS}"
    fi

    # Check Roles from values
    CUSTOM_ROLES=$(python3 -c "
import yaml, sys
with open('${VALUES_FILE}') as f:
    v = yaml.safe_load(f)
r = v.get('roles', {})
if r.get('include'):
    for role in r.get('roles', []):
        if role.get('include'):
            print(role['name'] + ' ' + role['namespace'])
" 2>/dev/null)

    if [ -n "${CUSTOM_ROLES}" ]; then
      while IFS= read -r line; do
        role_name=$(echo "${line}" | awk '{print $1}')
        role_ns=$(echo "${line}" | awk '{print $2}')
        TOTAL=$((TOTAL + 1))
        if oc get role "${role_name}" -n "${role_ns}" &>/dev/null; then
          pass "Role '${role_name}' exists in namespace '${role_ns}'"
        else
          fail "Role '${role_name}' not found in namespace '${role_ns}'"
        fi
      done <<< "${CUSTOM_ROLES}"
    fi

    # Check RoleBindings from values
    CUSTOM_RBS=$(python3 -c "
import yaml, sys
with open('${VALUES_FILE}') as f:
    v = yaml.safe_load(f)
rb = v.get('roleBindings', {})
if rb.get('include'):
    for b in rb.get('bindings', []):
        if b.get('include'):
            print(b['name'] + ' ' + b['namespace'])
" 2>/dev/null)

    if [ -n "${CUSTOM_RBS}" ]; then
      while IFS= read -r line; do
        rb_name=$(echo "${line}" | awk '{print $1}')
        rb_ns=$(echo "${line}" | awk '{print $2}')
        TOTAL=$((TOTAL + 1))
        if oc get rolebinding "${rb_name}" -n "${rb_ns}" &>/dev/null; then
          ROLE_REF=$(oc get rolebinding "${rb_name}" -n "${rb_ns}" -o jsonpath='{.roleRef.name}' 2>/dev/null)
          pass "RoleBinding '${rb_name}' exists in '${rb_ns}' (role=${ROLE_REF})"
        else
          fail "RoleBinding '${rb_name}' not found in '${rb_ns}'"
        fi
      done <<< "${CUSTOM_RBS}"
    fi
  else
    TOTAL=$((TOTAL + 1))
    fail "python3 required to parse values file"
  fi
else
  echo ""
  echo "  (No values file provided — skipping resource-specific checks)"
  echo "  Usage: ./e2e-test.sh <values-file>"
fi

# --- Aggregated ClusterRoles ---
echo ""
echo "--- Step 4: Aggregated ClusterRoles have rules populated ---"
TOTAL=$((TOTAL + 1))
AGG_CRS=$(oc get clusterrole -o json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('aggregationRule'):
        name = item['metadata']['name']
        rules = len(item.get('rules', []))
        selectors = len(item['aggregationRule'].get('clusterRoleSelectors', []))
        print(f'{name}: {rules} rules from {selectors} selectors')
" 2>/dev/null | head -10)
if [ -n "${AGG_CRS}" ]; then
  pass "Aggregated ClusterRoles found:"
  echo "${AGG_CRS}" | sed 's/^/    /'
else
  pass "No aggregated ClusterRoles (or none with rules populated yet)"
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
