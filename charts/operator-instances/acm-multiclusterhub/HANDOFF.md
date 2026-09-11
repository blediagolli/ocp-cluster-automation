# acm-multiclusterhub — Handoff

**Date:** 2026-09-04

## What it does
Deploys the ACM MultiClusterHub CR with configurable component toggles (console, insights, search, grc, cluster-lifecycle, siteconfig, volsync, cluster-proxy-addon, managedserviceaccount), availability config, node placement, and image pull secret.

## What was done this session
- Parameterized component overrides — each component is now individually toggleable via values
- Added nodeSelector, tolerations, imagePullSecret, annotations, and disableHubSelfManagement support
- Added conditional rendering for optional fields (empty objects/lists not emitted)

## Current state
- **Disabled** by default (`include: false`)
- Commented out in the hub ApplicationSet — uncomment `template: acm-multiclusterhub` in `cluster-config.yaml` to enable
- Not yet tested via ArgoCD sync

## Gotchas
- The `overrides.components` list must match what the MCH operator expects — invalid component names silently ignored
- `disableHubSelfManagement: true` prevents the hub from managing itself — only set if using a separate management cluster

## Testing

**Helm test** (`helm test <release>`): Checks MCH CR status is Running. ArgoCD does not run Helm test hooks — use for local validation only.

**E2E script** (`tests/e2e-test.sh`):
- Validates MCH phase is Running and all components report healthy
- Checks assisted-service, hive, and GitOpsCluster if enabled
- Reports per-component status with pass/fail summary
