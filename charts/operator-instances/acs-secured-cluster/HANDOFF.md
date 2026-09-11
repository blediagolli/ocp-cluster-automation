# acs-secured-cluster — Handoff

**Modified:** 2026-09-10

## What it does
Deploys the ACS SecuredCluster CR with sensor, collector, admission control, and ScannerV4. Supports 4 secret modes: `job` (init bundle from Central on same cluster), `preExisting` (certs in values), `external` (out-of-band), `generate` (calls Central API from managed cluster). Includes optional namespace creation and pre-existing TLS secrets.

## What changed this session
- `centralEndpoint` auto-derived from `cluster.baseDomain` — explicit override still required for managed clusters pointing to a remote Central
- `securedClusterNamespace.include` → `securedCluster.createNamespace` (namespace toggle nested under parent key)
- `clusterName` uses `cluster.name` from conf.yaml

## Current state
- **Enabled** on hub (`secretMode: "job"`) and dev (`secretMode: "generate"`)
- Hub: SecuredCluster reconciling with init-bundle from acs-central chart
- Dev: SecuredCluster synced and healthy

## Outstanding
- For prod clusters: set `secretMode: "generate"` in operator-instances.yaml

## Gotchas
- `securedCluster.createNamespace: false` on hub to avoid stackrox namespace conflict with acs-central
- `centralEndpoint` is auto-derived from hub's `cluster.baseDomain` — managed clusters must override it in operator-instances.yaml to point to the hub's Central route
- `secretMode: "generate"` requires `central-auth` secret — distributed automatically via ACM Policy when `initBundle.distributeAuth: true` is set on the hub
- Do NOT use `secretMode: "preExisting"` with empty cert values — creates empty secrets that block init-bundle
