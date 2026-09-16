# preserveResourcesOnDeletion in ApplicationSets

Controls whether Kubernetes resources survive when their managing Application or ApplicationSet is deleted. There are two independent levels, each protecting a different deletion path.

## Two levels

### 1. ApplicationSet level (`spec.syncPolicy.preserveResourcesOnDeletion`)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  syncPolicy:
    preserveResourcesOnDeletion: true   # ← this one
```

Protects against the **ApplicationSet controller** deleting Applications. This fires when:

- A generator stops producing a match (e.g., a `conf.yaml` is removed, a filter excludes a cluster)
- The ApplicationSet CR itself is deleted

With `true`: the Application CR is deleted, but the **child resources on the target cluster are left in place**. Without it: deleting the Application cascades into deleting everything it managed.

All 8 ApplicationSets in this repo have this set to `true`.

### 2. Application template level (`template.spec.syncPolicy.preserveResourcesOnDeletion`)

```yaml
  template:
    spec:
      syncPolicy:
        preserveResourcesOnDeletion: true   # ← this one (not currently set)
```

Protects against the **Application controller** deleting managed resources. This fires when:

- Someone deletes the Application CR directly (not via the AppSet controller)
- An external process or manual `oc delete` removes the Application

This is **not set** on our ApplicationSet templates — a direct Application delete would cascade into the managed resources.

## Interaction matrix

| Scenario | AppSet-level `true` | App-level `true` | Resources survive? |
|---|---|---|---|
| Generator stops matching | **yes** | irrelevant | **Yes** |
| Generator stops matching | no | yes | **Yes** (app has the flag) |
| Generator stops matching | no | no | **No** — cascade delete |
| Manual Application delete | irrelevant | **yes** | **Yes** |
| Manual Application delete | irrelevant | no | **No** |
| ApplicationSet itself deleted | **yes** | irrelevant | **Yes** |

The AppSet-level flag is the **outer shield** — prevents the AppSet controller from doing a cascading delete of the Application. The App-level flag is the **inner shield** — prevents the Application controller from cascading into managed resources.

## Migrating existing resources under an ApplicationSet

When an ApplicationSet-generated Application points at a git path containing manifests that match resources already on the cluster, ArgoCD **adopts** them on the first sync by adding the `app.kubernetes.io/instance` label.

### Requirements for clean adoption

1. Resources must match **exactly**: same `name`, `namespace`, `apiVersion`, `kind`
2. Any field drift between the live resource and git will be overwritten on sync (especially with `selfHeal: true`)
3. Resources on the cluster that are **not** in the git path won't be touched or managed

### Migration steps

1. Ensure the git path (overlay, chart, etc.) contains manifests matching the existing resources exactly
2. Add or update the `conf.yaml` so the generator produces a match for the target cluster
3. ArgoCD creates the Application, detects existing resources as OutOfSync, and syncs
4. On sync, ArgoCD takes ownership — from this point, git is the source of truth

### Risk windows

The dangerous moment is if the generator match breaks **after** adoption (bad path, removed `conf.yaml`, broken template). Without `preserveResourcesOnDeletion: true` at the AppSet level, this would delete the Application and cascade-delete all adopted resources.

With the flag set (as in this repo), a broken generator match leaves resources in place — the Application is removed but the cluster-side resources survive. Fix the generator, and the next sync re-adopts them.

### Pre-migration checklist

- [ ] Verify `preserveResourcesOnDeletion: true` is set on the target ApplicationSet
- [ ] Diff live resources against the git manifests — identify any field drift that ArgoCD will overwrite
- [ ] Check for resources with existing `app.kubernetes.io/instance` labels from a different Application (ArgoCD won't adopt resources already owned by another app)
- [ ] Ensure `selfHeal: true` behavior is acceptable — ArgoCD will revert any manual changes to adopted resources
- [ ] Test with a single non-critical resource before migrating a full set
