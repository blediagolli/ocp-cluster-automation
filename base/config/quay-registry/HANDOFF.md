# quay-registry — Handoff

## What it does
Deploys a Red Hat Quay registry instance via the `QuayRegistry` CR. Creates a dedicated namespace and configures all components as operator-managed (Clair, Postgres, object storage, Redis, HPA, route, mirror, monitoring, TLS).

## Current state
- **Not enabled** on any cluster (`include: false`)
- Not in any ApplicationSet element list
- Not tested
- References a `quay-registry-config-bundle` Secret that must exist before deployment

## Outstanding
- Config bundle secret (`quay-registry-config-bundle`) is hardcoded — should be parameterized in values.yaml
- All components are hardcoded to `managed: true` — add toggles for external Postgres, external object storage, or unmanaged TLS
- No resource limits or replica counts configured
- No storage class or PVC size configuration for managed Postgres/object storage
- Missing superuser credentials setup
- No Route/hostname customization
- Needs testing on a cluster with sufficient resources (Quay is resource-heavy)
