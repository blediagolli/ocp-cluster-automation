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

### 2. Fixed OutOfSync bootstrap resources
- Updated ArgoCD CR to include all operator-injected defaults (grafana, sso/dex, monitoring, notifications, prometheus, networkPolicy, imageUpdater, ha resources, server grpc/ingress/service, tls, initialSSHKnownHosts, controller processors/sharding, applicationSet webhookServer)
- Updated MultiClusterHub CR: added `localClusterName: local-cluster`, removed stale `storageClass`

### 2. Renamed app-of-apps to `platform-root`
- Changed Application name from `openshift-gitops-config` (operator default) to `platform-root`
- Old Application had no finalizers — non-cascading delete was safe

### 3. Moved ACM from bootstrap to Helm charts
- ACM operator (Subscription, Namespace, OperatorGroup) now managed by `operator-deployment` chart
  - Channel updated to `release-2.17` to match bootstrap source of truth
  - Added `namespaceAnnotations`/`namespaceLabels` support to operator-deployment namespace template
- ACM instance now managed by `acm-multiclusterhub` operator-instances chart:
  - MultiClusterHub CR with CRD wait and MCH wait jobs (ArgoCD sync hooks)
  - Assisted-service (AgentServiceConfig + ConfigMap) — togglable via `assistedService.include`
  - Hive (HiveConfig + Provisioning) — togglable via `hiveConfig.include`
  - GitOps-cluster (GitOpsCluster + ManagedClusterSetBinding + Placement) — togglable via `gitopsCluster.include`
  - Console plugins (Job to enable acm/mce plugins) — togglable via `consolePlugins.include`
- Removed entire `bootstrap/advanced-cluster-management/` directory

### 4. Moved OpenShift GitOps from bootstrap to Helm charts
- GitOps operator Subscription now managed by `operator-deployment` chart (channel `gitops-1.21`)
- New `openshift-gitops-instance` operator-instances chart manages:
  - ArgoCD CR — togglable via `argocd.include`
  - Cluster-admin ClusterRoleBinding — togglable via `clusterRoleBinding.include`
  - `platform` AppProject — togglable via `appProject.include`
  - Console plugin job — togglable via `consolePlugin.include`
- Bootstrap directory retained for initial manual `oc apply` only — removed from `platform-root` kustomization
- Bootstrap is now a one-time seed; all ongoing management is through the Helm charts
- Cleaned up stale hook resources (ServiceAccounts, Jobs, ClusterRoles, ClusterRoleBindings) from `platform-root` tracking

## Previous session changes

1. **Collapsed redundant ApplicationSet toggles** — `deployOperators` (top-level bool) and `managedCluster.deploy` replace explicit toggle fields
2. **Added type labels to all ApplicationSets** — `environment`, `cluster`, `type` on every Application template
3. **Enabled auto-sync everywhere** — `automated.selfHeal` on all ApplicationSets
4. **Cleaned up non-included operators** — MGT: 34 → 9, DEV: 34 → 3, PROD: all removed
5. **Team onboarding** — `onboarding-gitops` and `onboarding-namespaces` ApplicationSets with t-shirt sizing
6. **Repository restructure** — `base/` → `charts/` (grouped), `conf/` → `env/`, flat → categorized
7. **Split ApplicationSets and values files** — `cluster-config` → `cluster-platform-config` + `cluster-operator-instances`, monolithic conf.yaml split into category-specific files

## Current state

### Repository structure
```
bootstrap/                     # one-time oc apply seed (GitOps operator + ArgoCD)
charts/
  operator-deployment/         # operator Subscription chart (Namespace, OG, Sub)
  operator-instances/          # 28 operator CR instance charts
    acm-multiclusterhub/       #   MCH + assisted-service, hive, gitops-cluster, console plugins
    openshift-gitops-instance/ #   ArgoCD CR, ClusterRoleBinding, AppProject, console plugin
    acs-central/               #   ACS Central + init bundle
    acs-secured-cluster/       #   SecuredCluster
    ...                        #   25 more operator instance charts
  platform-config/             # 28 OpenShift platform config charts
  onboarding/                  # application-gitops, namespace-config
  cluster-provisioning/        # cluster provisioning
env/<env>/
  conf.yaml                    # shared environment config
  platform-config.yaml         # platform chart values
  operator-instances.yaml      # operator instance chart values
  operator-deployment.yaml     # operator Subscription defaults
  namespace-sizes.yaml         # t-shirt size definitions
clusters/<env>/<cluster>/
  conf.yaml                    # cluster metadata, chart lists, deploy toggles
  platform-config.yaml         # cluster-level platform overrides
  operator-instances.yaml      # cluster-level operator instance overrides
  operator-deployment.yaml     # cluster-level operator Subscriptions
  namespace-sizes.yaml         # cluster-level size overrides (optional)
  teams/
    team-alpha.yaml            # team definition with sized namespaces
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
└── config-dev-cluster-lz5bn-* (platform-config + operator-instances)
    └── 9 config/instance Applications for dev cluster
```

### Bootstrap flow (new cluster setup)
1. `oc apply -k clusters/mgt/acm-hub/bootstrap/` — installs GitOps operator + ArgoCD instance
2. Manually create `platform-root` Application pointing to `clusters/mgt/acm-hub/`
3. ArgoCD takes over — syncs ApplicationSets, operator-deployment, operator-instances
4. All ongoing management is through git commits

### Team onboarding flow
1. Create `clusters/<env>/<cluster>/teams/<team>.yaml`
2. ArgoCD auto-creates two Applications: namespace provisioning + ArgoCD instance
3. Team gets their own ArgoCD at `<team>-gitops` with admin access

## Gotchas
- `deployOperators` must be top-level in conf.yaml, NOT inside the `operators` map — the chart iterates all keys in `operators` as Subscriptions
- `managedCluster.deploy` is safe inside the map because the import chart only ranges over `managedCluster.labels`, not top-level keys
- `missingkey=error` means you can't use `.foo` dot notation on keys that might not exist — use `index . "foo"` instead
- Onboarding ApplicationSets use a matrix generator to pair `conf.yaml` with team files — team files only define `team.*`, no `cluster.*` duplication needed
- `ignoreMissingValueFiles: true` on all ApplicationSets — files at any level are optional
- Renaming an ApplicationSet resource causes ArgoCD to delete the old and create the new — Applications with unchanged names are adopted
- `platform-root` is self-managing — changes to `applications/app-argocd.yaml` sync automatically, but if it breaks, manual `oc apply` is the recovery path
- ArgoCD hook resources (sync-wave Jobs) don't get pruned automatically — delete manually if they become stale after restructuring
- The ArgoCD CR has many operator-injected defaults (grafana, sso, monitoring, etc.) — the `openshift-gitops-instance` chart includes all of them to stay in sync

## Outstanding
- Team GitOps provisioning not yet tested end-to-end on a live cluster
- No NetworkPolicy template in namespace-config yet
