# acm-managed-cluster — Handoff

**Modified:** 2026-09-10

## What it does
Registers a managed cluster with ACM hub. Creates: ManagedCluster, KlusterletAddonConfig, ManagedClusterAddons, auto-import Secret (kubeconfig or token mode), and ArgoCD cluster secret registration.

## What changed this session
- `managedCluster.name` and `managedCluster.environment` removed from values — templates now reference `cluster.name` and `cluster.environment` from conf.yaml (single source of truth)
- `managedCluster` config moved from conf.yaml to platform-config.yaml
- `deployImport` boolean in conf.yaml controls Application generation (replaces old `managedCluster.deploy`)

## Current state
- Used via the `cluster-import` ApplicationSet with `deployImport` toggle
- Hub cluster `local-cluster` auto-imported
- Dev cluster `cluster-lz5bn` imported and Joined/Available via ACM

## Outstanding
- Auto-import secret contains credentials — `kubeconfig` and `token` values should use sealed-secrets or external-secrets
- No cluster destroy/detach — removing a cluster from conf.yaml leaves ManagedCluster orphaned; needs prune policy
- Token mode (`autoImport.mode: token`) does not trigger the ArgoCD register Job — only kubeconfig mode is wired

## Gotchas
- Do NOT add `name` or `environment` under `managedCluster` in values — templates use `cluster.name` and `cluster.environment` from conf.yaml
- `managedCluster` config belongs in `platform-config.yaml`, not `conf.yaml`

## Testing

**Helm test** (`helm test <release>`): Checks ManagedCluster is joined and ManagedClusterAddOns exist. ArgoCD does not run Helm test hooks — use for local validation only.

**E2E script** (`tests/e2e-test.sh <cluster-name>`):
- Validates ManagedCluster joined and available conditions
- Checks per-addon status (Available=True)
- Verifies ArgoCD cluster secret exists in openshift-gitops
