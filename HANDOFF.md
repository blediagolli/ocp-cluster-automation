# Session Handoff

**Modified:** 2026-09-10

## What changed this session

### 1. Collapsed redundant ApplicationSet toggles
- Removed `operatorApps` and `importApps` fields from all cluster conf.yaml files
- ApplicationSets now derive the toggle from the data blocks directly using `deployOperators` (top-level bool) and `managedCluster.deploy`
- Used `index` for safe key lookup to avoid `missingkey=error` failures when a conf.yaml omits a block entirely
- `deployOperators` is top-level (not inside `operators` map) to avoid collision with the operators chart which iterates `range $name, $operator := .Values.operators`

### 2. Added type labels to all ApplicationSets
- Added `type` label to every ApplicationSet template
- Added `environment`, `cluster`, `type` labels to app-of-apps root Application
- Dropped `managed-by` and `part-of` labels — redundant when everything is ApplicationSet-managed under `project: platform`

### 3. Enabled auto-sync everywhere
- Enabled `automated.selfHeal` on app-of-apps, config-overlays, and provisioning
- Requires one manual sync of app-of-apps to bootstrap the auto-sync setting

### 4. Cleaned up non-included operators
- Removed operator entries without `include: true` from all cluster conf files
- MGT: 34 → 7 operators, DEV: 34 → 3, PROD: all removed (`operators: {}`) since `deployOperators: false`

### 5. Team onboarding (new feature)
- **ApplicationSet `onboarding-gitops`** — reads `clusters/**/teams/*.yaml`, provisions per-team ArgoCD instances
- **ApplicationSet `onboarding-namespaces`** — reads same team files, provisions namespaces with RQ/LR sizing
- **Charts:** `charts/onboarding/application-gitops` and `charts/onboarding/namespace-config`
- T-shirt sizing (small/medium/large) with chart defaults → env → cluster override chain

### 6. Repository restructure
- `base/` flattened to `charts/` with grouped subdirectories:
  - `charts/operator-deployment/` — operator Subscription chart
  - `charts/operator-instances/` — 27 operator CR instance charts
  - `charts/platform-config/` — 28 OpenShift platform config charts
  - `charts/onboarding/` — team provisioning charts
  - `charts/cluster-provisioning/` — cluster provisioning chart
- `conf/` renamed to `env/`

### 7. Split ApplicationSets and values files by chart category
- Split `cluster-config` ApplicationSet into `cluster-platform-config` and `cluster-operator-instances`
- Split monolithic conf.yaml into category-specific values files at both env and cluster levels:
  - `conf.yaml` — shared cluster metadata, chart lists, deploy toggles
  - `platform-config.yaml` — values for platform-config charts
  - `operator-instances.yaml` — values for operator-instance charts
  - `operator-deployment.yaml` — operator Subscription config
  - `namespace-sizes.yaml` — t-shirt size definitions (onboarding)
- Each ApplicationSet loads `conf.yaml` (shared) plus its category-specific file
- `ignoreMissingValueFiles: true` on all ApplicationSets so files are optional at any level
- `configCharts` replaced by `platformCharts` and `operatorInstanceCharts` in conf.yaml
- Config-overlays ApplicationSet now togglable via `deployOverlay` in conf.yaml

## Current state

### Repository structure
```
charts/
  operator-deployment/     # operator Subscription chart
  operator-instances/      # 27 operator CR instance charts
  platform-config/         # 28 OpenShift platform config charts
  onboarding/              # application-gitops, namespace-config
  cluster-provisioning/    # cluster provisioning
env/<env>/
  conf.yaml                # shared environment config (cluster.registry)
  platform-config.yaml     # platform chart values
  operator-instances.yaml  # operator instance chart values
  operator-deployment.yaml # operator Subscription defaults
  namespace-sizes.yaml     # t-shirt size definitions
clusters/<env>/<cluster>/
  conf.yaml                # cluster metadata, chart lists, deploy toggles, managedCluster
  platform-config.yaml     # cluster-level platform overrides
  operator-instances.yaml  # cluster-level operator instance overrides
  operator-deployment.yaml # cluster-level operator Subscriptions
  namespace-sizes.yaml     # cluster-level size overrides (optional)
  teams/
    team-alpha.yaml        # team definition with sized namespaces
```

### ApplicationSets (8 total)
| ApplicationSet | Generator source | Type label |
|---|---|---|
| cluster-operators | `conf.yaml` + `deployOperators` | operators |
| cluster-platform-config | `conf.yaml` + `platformCharts` | platform-config |
| cluster-operator-instances | `conf.yaml` + `operatorInstanceCharts` | operator-instances |
| cluster-config-overlays | `conf.yaml` + `deployOverlay` | config-overlay |
| cluster-import | `conf.yaml` + `managedCluster.deploy` | import |
| cluster-provisioning | `provision.yaml` | provisioning |
| onboarding-gitops | `teams/*.yaml` | onboarding-gitops |
| onboarding-namespaces | `teams/*.yaml` | onboarding-namespaces |

### Team onboarding flow
1. Create `clusters/<env>/<cluster>/teams/<team>.yaml`
2. ArgoCD auto-creates two Applications: namespace provisioning + ArgoCD instance
3. Team gets their own ArgoCD at `<team>-gitops` with admin access

## Gotchas
- `deployOperators` must be top-level in conf.yaml, NOT inside the `operators` map — the chart iterates all keys in `operators` as Subscriptions
- `managedCluster.deploy` is safe inside the map because the import chart only ranges over `managedCluster.labels`, not top-level keys
- `missingkey=error` means you can't use `.foo` dot notation on keys that might not exist — use `index . "foo"` instead
- Team files duplicate `cluster.*` (3 lines) because the git file generator reads one file — it can't merge with conf.yaml
- App-of-apps needs one manual sync to bootstrap its own auto-sync setting
- `ignoreMissingValueFiles: true` on all ApplicationSets — files at any level are optional
- Renaming an ApplicationSet resource causes ArgoCD to delete the old and create the new — Applications with unchanged names are adopted

### 8. Fixed OutOfSync bootstrap resources
- Updated ArgoCD CR (`clusters/mgt/acm-hub/bootstrap/openshift-gitops/instance/argocd.yaml`) to include all operator-injected defaults: grafana, sso/dex, monitoring, notifications, prometheus, networkPolicy, imageUpdater, ha resources, server grpc/ingress/service, tls, initialSSHKnownHosts, controller processors/sharding, applicationSet webhookServer
- Updated MultiClusterHub CR (`clusters/mgt/acm-hub/bootstrap/advanced-cluster-management/instance/acm-multiclusterhub.yaml`): added `localClusterName: local-cluster`, removed `storageClass` (not present in live state)
- App-of-apps (`openshift-gitops-config`) now fully Synced with zero out-of-sync resources

## Outstanding
- Team GitOps provisioning not yet tested end-to-end on a live cluster
- No NetworkPolicy template in namespace-config yet
- `env/mgt/namespace-sizes.yaml` does not exist — create if mgt cluster needs team onboarding
