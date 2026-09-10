# acs-secured-cluster — Handoff

**Modified:** 2026-09-08

## What it does
Deploys the ACS SecuredCluster CR with sensor, collector, admission control, and ScannerV4. Supports 4 secret modes: `job` (init bundle from Central on same cluster), `preExisting` (certs in values), `external` (out-of-band), `generate` (calls Central API from managed cluster). Includes optional namespace creation and pre-existing TLS secrets.

## What changed this session
- Added `secretMode: "generate"` — PostSync Job that calls Central's `/v1/cluster-init/init-bundles` API from the managed cluster to auto-generate TLS secrets. Reads admin password from `central-auth` secret (distributed by ACM Policy from acs-central chart).
- Fixed hub config: `secretMode: "job"` to prevent empty placeholder secrets
- Renamed dev cluster from `dev.example.com` to `cluster-lz5bn`

## Current state
- **Enabled** on hub (`secretMode: "job"`) and dev (`secretMode: "generate"`)
- Hub: SecuredCluster reconciling with init-bundle from acs-central chart
- Dev: pending ACM Policy distribution of `central-auth` secret + ArgoCD sync

## Outstanding
- Verify `generate` mode works end-to-end on dev cluster after ACM Policy distributes credentials
- For prod clusters: set `secretMode: "generate"` in `conf/prod/conf.yaml`

## Gotchas
- `securedClusterNamespace.include: false` on hub to avoid stackrox namespace conflict with acs-central
- `secretMode: "generate"` requires `central-auth` secret — distributed automatically via ACM Policy when `central.initBundle.distributeAuth: true` is set on the hub
- Do NOT use `secretMode: "preExisting"` with empty cert values — creates empty secrets that block init-bundle
