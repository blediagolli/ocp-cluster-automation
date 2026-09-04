# acs-secured-cluster — Handoff

**Modified:** 2026-09-04

## What it does
Deploys the ACS SecuredCluster CR with sensor, collector, admission control, and ScannerV4. Supports 3 secret modes: `job` (init bundle from Central), `preExisting` (certs in values), `external` (out-of-band). Includes optional namespace creation and pre-existing TLS secrets.

## What changed this session
- Added `secretMode` with 3 options (job/preExisting/external) for flexible cert management
- Added `pre-existing-secrets.yaml` template for manual cert injection
- Added admission control `failurePolicy`, `scannerV4.scannerComponent`, network policies toggle, custom envVars, VM scanning, and OpenShift monitoring integration
- Added `securedClusterNamespace` toggle for namespace creation
- **Fixed hub config**: Changed `secretMode` from default `preExisting` to `job` — the preExisting mode was creating empty placeholder secrets that blocked the init-bundle Job from generating real TLS data

## Current state
- **Enabled** on hub (`securedCluster.include: true`, `secretMode: "job"`)
- SecuredCluster currently in `Irreconcilable` state due to empty TLS secrets — will self-heal on next ArgoCD sync after init-bundle regenerates secrets
- Hub uses `centralEndpoint: central-stackrox.apps.cluster-c8444...`

## Outstanding
- Verify SecuredCluster reconciles successfully after init-bundle regenerates TLS secrets
- For remote/managed clusters: need to implement init-bundle distribution (external-secrets or manual cert injection via `secretMode: preExisting`)

## Gotchas
- `securedClusterNamespace.include: false` on hub to avoid stackrox namespace conflict with acs-central
- For remote clusters, set `secretMode: preExisting` and populate cert values, or use external-secrets
- Do NOT use `secretMode: preExisting` with empty cert values — it creates empty secrets that prevent init-bundle from running
