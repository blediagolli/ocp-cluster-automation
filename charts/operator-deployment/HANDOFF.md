# operator-deployment — Handoff

**Modified:** 2026-09-11

## What it does
Deploys operator Subscriptions, Namespaces, and OperatorGroups for all enabled operators. Each operator is toggled via `operators.<name>.include`. Supports cluster-scoped operators, shared namespaces (`skipNamespace`/`skipOperatorGroup`), custom namespace labels/annotations, and per-operator channel pinning.

## Current state
- **Hub**: 9 operators enabled (gitops, ACM, ACS, AAP, quay, quay-bridge, compliance, odf, cert-manager)
- **Dev/Prod**: 2 operators (gitops, ACS)

## Gotchas
- `channel: change-me` on many operators — must be set before enabling
- Operators using `skipNamespace: true` share `openshift-operators` — no dedicated OperatorGroup
- `installPlanApproval: Automatic` is hardcoded — all operators auto-upgrade on channel

## Testing

**Helm test** (`helm test <release>`): Checks each enabled operator's Subscription has a currentCSV in Succeeded phase. ArgoCD does not run Helm test hooks — use for local validation only.

**E2E script** (`tests/e2e-test.sh`):
- Discovers all Subscriptions cluster-wide
- Validates each has a currentCSV and its CSV phase is Succeeded
- Reports pass/fail per operator with summary totals
