# acs-central — Handoff

**Modified:** 2026-09-10

## What it does
Deploys ACS Central Services (Central, Scanner, ScannerV4, DB) with route/LB/nodePort exposure options. Includes optional init-bundle Job (generates TLS secrets for SecuredCluster), ConsoleLink, namespace creation, and ACM Policy for distributing Central credentials to managed clusters.

## What changed this session
- `centralUrl` auto-derived from `cluster.baseDomain` — no longer needs explicit override
- Flattened values: `central.initBundle` → top-level `initBundle`, `central.consoleLink` → top-level `centralConsoleLink`
- `centralNamespace.include` → `central.createNamespace` (namespace toggle nested under parent key)

## Current state
- **Enabled** on hub with init-bundle and credential distribution
- Central v4.11.3 running, all pods healthy
- ACM Policy distributes `central-auth` to dev/prod clusters

## Gotchas
- Init-bundle Job requires Central to be healthy — uses a PostSync hook
- `centralUrl` is auto-derived from `cluster.baseDomain` — override in operator-instances.yaml only if the route hostname differs
- `distributeAuth` uses ACM hub-templates to read `central-htpasswd` secret — if the secret name changes, update the Policy template
- `targetEnvironments` controls which clusters receive the credential (default: dev, prod)

## Testing

**Helm test** (`helm test <release>`): Checks Central CR has Deployed=True condition. ArgoCD does not run Helm test hooks — use for local validation only.

**E2E script** (`tests/e2e-test.sh [namespace]`): defaults to `stackrox`
- Validates Central CR status, pods running, and route accessible via `/v1/ping`
- Checks init-bundle job completed and scanner pods running
- Reports 5-step pass/fail summary
