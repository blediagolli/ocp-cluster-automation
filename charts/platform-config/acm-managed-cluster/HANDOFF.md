# acm-managed-cluster — Handoff

**Modified:** 2026-09-16

## What it does
Registers a managed cluster with ACM hub. Creates: ManagedCluster, KlusterletAddonConfig, ManagedClusterAddons, auto-import Secret (kubeconfig or token mode), and ArgoCD cluster secret registration.

## What changed this session
- **Static guard**: `managed-cluster.yaml` fails with a clear error if `deployProvision` is true — ACM-provisioned clusters are already imported, using cluster-import would conflict
- **Dynamic PreSync check**: `presync-check-existing.yaml` runs a Job before sync that queries `oc get managedcluster <name>` — blocks import if the cluster already exists in ACM (e.g. provisioned via ACM console or another repo)
- Uses `index .Values "deployProvision"` for safe nil handling when the key isn't in the value files

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
- Do NOT enable `deployImport` for ACM-provisioned clusters — Hive already creates the ManagedCluster; the static guard will fail the template, and the PreSync Job will block sync if the cluster exists in ACM from any source

## Testing

**Template tests** (`tests/template-test.sh`): 30 assertions, no cluster required.
- Static guard: fails when `deployProvision=true` + `managedCluster.include=true`
- PreSync Job: Job, SA, ClusterRole, ClusterRoleBinding rendered with correct hooks
- ManagedCluster, addons, auto-import rendering and toggle behavior

**Helm test** (`helm test <release>`): Checks ManagedCluster is joined and ManagedClusterAddOns exist. ArgoCD does not run Helm test hooks — use for local validation only.

**E2E script** (`tests/e2e-test.sh <cluster-name>`):
- Validates ManagedCluster joined and available conditions
- Checks per-addon status (Available=True)
- Verifies ArgoCD cluster secret exists in openshift-gitops
