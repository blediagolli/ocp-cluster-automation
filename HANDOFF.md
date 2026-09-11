# Session Handoff

**Modified:** 2026-09-10

## What changed this session

### 1. Values refactoring — flattened nesting and auto-derived URLs
- **acs-central**: Moved `central.initBundle` → top-level `initBundle`, `central.consoleLink` → top-level `centralConsoleLink`; `centralUrl` auto-derived from `cluster.baseDomain`
- **acs-secured-cluster**: `centralEndpoint` auto-derived from `cluster.baseDomain` (explicit override still required for managed clusters pointing to remote Central)
- **quay-registry**: Flattened `quayRegistry.bridge` → `quayBridge`, `quayRegistry.keycloak` → `quayKeycloak`; `quayHostname` auto-derived from `cluster.baseDomain`
- **acm-observability**: Renamed `consoleLink` → `observabilityConsoleLink`; `href` auto-derived from `cluster.baseDomain`; `storageClass` uses `cluster.storageClass`; OBC namespace uses `multiClusterObservability.namespace`
- **user-workload-monitoring**: `storageClass` falls back to `cluster.storageClass`
- **conf.yaml**: Added `cluster.baseDomain` (all clusters) and `cluster.storageClass` (mgt)
- **operator-instances.yaml overrides**: Removed redundant URLs (now derived), cleaned up redundant AAP defaults, updated to match new flattened structure

### 2. Purpose comments on all values files
- Added a comment block at the top of every values file (30+ files across `env/`, `clusters/`, and `teams/`) explaining what the file controls, its scope, and where it sits in the precedence chain

### 3. Centralized team definitions
- Team files moved from cluster-scoped directories (`clusters/.../teams/team-alpha.yaml`) to root-level `teams/` directory
- Onboarding ApplicationSets refactored from git file generators to matrix generators with `elementsYaml` — same pattern as `platformCharts`
- `conf.yaml` gains a `teams` list (e.g. `teams: [{team: team-alpha}]`); empty `teams: []` required in every conf.yaml due to `missingkey=error`
- Values file chain: `teams/<team>.yaml` → `env/<env>/conf.yaml` → `env/<env>/teams/<team>.yaml` → `clusters/.../conf.yaml` → `clusters/.../teams/<team>.yaml`
- Team definition (`teams/<team>.yaml`) contains only `team.*` values; `cluster.*` comes from `conf.yaml` via the matrix generator

### 4. Redundant values cleanup (97 lines removed)
- Removed all env-level and cluster-level values that duplicated chart defaults
- `env/*/platform-config.yaml` — cleared all three (every entry was `include: false` matching chart defaults)
- `env/dev/operator-instances.yaml` — removed `scanSetting`/`scanSettingBinding` defaults
- `env/*/operator-deployment.yaml` — removed operators already excluded by chart defaults
- `clusters/mgt/acm-hub/platform-config.yaml` — removed etcd defaults, monitoring requests, storageClass
- `clusters/mgt/acm-hub/operator-instances.yaml` — removed `securedClusterNamespace`, `quayNamespace`, flattened remaining overrides

### 5. Namespace toggles nested under parent keys
- Separate `*Namespace.include` top-level keys replaced with `createNamespace` nested under the parent key:
  - `securedClusterNamespace.include` → `securedCluster.createNamespace`
  - `centralNamespace.include` → `central.createNamespace`
  - `quayNamespace.include` → `quayRegistry.createNamespace`, `quayNamespace.name` → `quayRegistry.namespace`
  - `observabilityNamespace.include` → `multiClusterObservability.createNamespace`

### 6. managedCluster config moved and deduplicated
- `managedCluster` block moved from `conf.yaml` to `platform-config.yaml` (it's a platform-config chart, not ApplicationSet metadata)
- `managedCluster.name` and `managedCluster.environment` removed from chart values — all 5 template files now reference `cluster.name` and `cluster.environment` (single source of truth from conf.yaml)
- `deployImport` boolean in `conf.yaml` controls whether the cluster-import ApplicationSet generates an Application (replaces old `managedCluster.deploy`)

## Previous session changes

1. **Fixed OutOfSync bootstrap resources** — ArgoCD CR includes all operator-injected defaults; MultiClusterHub CR aligned
2. **Renamed app-of-apps to `platform-root`** — from `openshift-gitops-config` (operator default)
3. **Moved ACM from bootstrap to Helm charts** — operator-deployment + acm-multiclusterhub operator-instances chart
4. **Moved OpenShift GitOps from bootstrap to Helm charts** — operator-deployment + openshift-gitops-instance chart; bootstrap retained as one-time seed only
5. **Collapsed redundant ApplicationSet toggles** — `deployOperators` (top-level bool) replaces explicit toggle fields
6. **Added type labels to all ApplicationSets** — `environment`, `cluster`, `type` on every Application template
7. **Enabled auto-sync everywhere** — `automated.selfHeal` on all ApplicationSets
8. **Cleaned up non-included operators** — MGT: 34 → 9, DEV: 34 → 3, PROD: all removed
9. **Team onboarding** — `onboarding-gitops` and `onboarding-namespaces` ApplicationSets with t-shirt sizing
10. **Repository restructure** — `base/` → `charts/` (grouped), `conf/` → `env/`, flat → categorized
11. **Split ApplicationSets and values files** — `cluster-config` → `cluster-platform-config` + `cluster-operator-instances`, monolithic conf.yaml split into category-specific files

## Current state

### Repository structure
```
bootstrap/                     # one-time oc apply seed (GitOps operator + ArgoCD)
charts/
  operator-deployment/         # operator Subscription chart (Namespace, OG, Sub)
  operator-instances/          # operator CR instance charts
    acm-multiclusterhub/       #   MCH + assisted-service, hive, gitops-cluster, console plugins
    openshift-gitops-instance/ #   ArgoCD CR, ClusterRoleBinding, AppProject, console plugin
    acs-central/               #   ACS Central + init bundle
    acs-secured-cluster/       #   SecuredCluster
    ...                        #   more operator instance charts
  platform-config/             # OpenShift platform config charts
    acm-managed-cluster/       #   ManagedCluster, auto-import, klusterlet, addons
    ...                        #   more platform config charts
  onboarding/                  # application-gitops, namespace-config
  cluster-provisioning/        # cluster provisioning
teams/
  <team>.yaml                  # central team definition (name, admins, repo, namespaces)
env/<env>/
  conf.yaml                    # shared environment config (cluster.environment)
  platform-config.yaml         # platform chart values (overrides chart defaults)
  operator-instances.yaml      # operator instance chart values
  operator-deployment.yaml     # operator Subscription defaults
  namespace-sizes.yaml         # t-shirt size definitions
  teams/<team>.yaml            # env-level team overrides (optional)
clusters/<env>/<cluster>/
  conf.yaml                    # cluster identity, chart lists, deploy toggles, teams list
  platform-config.yaml         # cluster-level platform overrides (incl. managedCluster config)
  operator-instances.yaml      # cluster-level operator instance overrides
  operator-deployment.yaml     # cluster-level operator Subscriptions
  namespace-sizes.yaml         # cluster-level size overrides (optional)
  teams/<team>.yaml            # cluster-level team overrides (optional)
```

### conf.yaml required fields
Every `clusters/.../conf.yaml` must include (due to `missingkey=error`):
```yaml
cluster:
  name: <name>
  environment: <env>
  address: <api-url>
platformCharts: []       # or list of {chart: <name>}
operatorInstanceCharts: [] # or list of {chart: <name>}
deployOperators: false   # or true
deployOverlay: false     # or true
deployImport: false      # or true
teams: []                # or list of {team: <name>}
```

### ApplicationSets (8 total)
| ApplicationSet | Generator source | Type label |
|---|---|---|
| cluster-operators | `conf.yaml` + `deployOperators` | operators |
| cluster-platform-config | `conf.yaml` + `platformCharts` | platform-config |
| cluster-operator-instances | `conf.yaml` + `operatorInstanceCharts` | operator-instances |
| cluster-config-overlays | `conf.yaml` + `deployOverlay` | config-overlay |
| cluster-import | `conf.yaml` + `deployImport` | import |
| cluster-provisioning | `provision.yaml` | provisioning |
| onboarding-gitops | `conf.yaml` + `teams` | onboarding-gitops |
| onboarding-namespaces | `conf.yaml` + `teams` | onboarding-namespaces |

### Management hierarchy
```
platform-root (Application)
├── 8 ApplicationSets (above)
├── platform-root itself (self-managing)
│
├── acm-hub-operators (operator-deployment chart)
│   └── Subscriptions: openshift-gitops, ACM, ACS, AAP, cluster-observability,
│       external-secrets, logging, quay, quay-bridge
│
├── config-mgt-acm-hub-openshift-gitops-instance
│   └── ArgoCD CR, ClusterRoleBinding, AppProject, console plugin
│
├── config-mgt-acm-hub-acm-multiclusterhub
│   └── MCH, assisted-service, hive, gitops-cluster, console plugins
│
├── config-mgt-acm-hub-* (platform-config + operator-instances)
│   └── 12 config/instance Applications for acm-hub
│
├── import-dev-cluster-lz5bn (acm-managed-cluster chart)
│   └── ManagedCluster, auto-import secret, klusterlet addon
│
├── config-dev-cluster-lz5bn-* (platform-config + operator-instances)
│   └── 9 config/instance Applications for dev cluster
│
└── onboarding-gitops-dev-cluster-lz5bn-team-alpha
    └── team-alpha ArgoCD instance on dev cluster
```

### Bootstrap flow (new cluster setup)
1. `oc apply -k clusters/mgt/acm-hub/bootstrap/` — installs GitOps operator + ArgoCD instance
2. Manually create `platform-root` Application pointing to `clusters/mgt/acm-hub/`
3. ArgoCD takes over — syncs ApplicationSets, operator-deployment, operator-instances
4. All ongoing management is through git commits

### Team onboarding flow
1. Create `teams/<team>.yaml` with team name, admins group, repo, and namespaces
2. Add `- team: <team>` to the `teams` list in each target cluster's `conf.yaml`
3. (Optional) Create `env/<env>/teams/<team>.yaml` or `clusters/.../<team>.yaml` for overrides
4. ArgoCD auto-creates two Applications per cluster: namespace provisioning + ArgoCD instance
5. Team gets their own ArgoCD at `<team>-gitops` with admin access

### Values precedence chain
All ApplicationSets use `ignoreMissingValueFiles: true`, so any level is optional:
```
chart defaults (values.yaml)
  < env/<env>/conf.yaml
  < env/<env>/<category>.yaml
  < clusters/<env>/<cluster>/conf.yaml
  < clusters/<env>/<cluster>/<category>.yaml
```
For team onboarding, the chain is:
```
chart defaults < teams/<team>.yaml < env conf < env teams override < cluster conf < cluster teams override
```

## Gotchas
- `deployOperators` must be top-level in conf.yaml, NOT inside the `operators` map — the chart iterates all keys in `operators` as Subscriptions
- `deployImport` controls whether the cluster-import ApplicationSet creates an Application; `managedCluster` config lives in `platform-config.yaml`, not `conf.yaml`
- `managedCluster` templates reference `cluster.name` and `cluster.environment` from conf.yaml — do NOT add `name`/`environment` under `managedCluster` in values
- `missingkey=error` means you can't use `.foo` dot notation on keys that might not exist — use `index . "foo"` instead
- `teams: []` is required in every conf.yaml even if the cluster has no teams
- Namespace creation toggles are nested under parent keys (e.g. `securedCluster.createNamespace`, not `securedClusterNamespace.include`)
- `ignoreMissingValueFiles: true` on all ApplicationSets — files at any level are optional
- Renaming an ApplicationSet resource causes ArgoCD to delete the old and create the new — Applications with unchanged names are adopted
- `platform-root` is self-managing — changes to `applications/app-argocd.yaml` sync automatically, but if it breaks, manual `oc apply` is the recovery path
- ArgoCD hook resources (sync-wave Jobs) don't get pruned automatically — delete manually if they become stale after restructuring
- The ArgoCD CR has many operator-injected defaults (grafana, sso, monitoring, etc.) — the `openshift-gitops-instance` chart includes all of them to stay in sync

## Outstanding
- No NetworkPolicy template in namespace-config yet
