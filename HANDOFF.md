# Session Handoff

**Modified:** 2026-09-10

## What changed this session

### 1. Collapsed redundant ApplicationSet toggles
- Removed `operatorApps` and `importApps` fields from all cluster conf.yaml files
- ApplicationSets now derive the toggle from the data blocks directly using `deployOperators` (top-level bool) and `managedCluster.deploy`
- Used `index` for safe key lookup to avoid `missingkey=error` failures when a conf.yaml omits a block entirely
- `deployOperators` is top-level (not inside `operators` map) to avoid collision with the operators chart which iterates `range $name, $operator := .Values.operators`

### 2. Added type labels to all ApplicationSets
- Added `type` label to every ApplicationSet template: `operators`, `config`, `config-overlay`, `import`, `provisioning`, `team-gitops`, `team-namespaces`
- Added `environment`, `cluster`, `type` labels to app-of-apps root Application
- Dropped `managed-by` and `part-of` labels — redundant when everything is ApplicationSet-managed under `project: platform`

### 3. Enabled auto-sync everywhere
- Enabled `automated.selfHeal` on app-of-apps, config-overlays, and provisioning — the three that previously had `syncPolicy: {}`
- Requires one manual sync of app-of-apps to bootstrap the auto-sync setting

### 4. Cleaned up non-included operators
- Removed operator entries without `include: true` from all cluster conf files
- MGT: 34 → 7 operators, DEV: 34 → 3, PROD: all removed (`operators: {}`) since `deployOperators: false`
- Hub `importApps` was also removed — hub doesn't need an import Application

### 5. Team GitOps instance provisioning (new feature)
- **New ApplicationSet:** `application-gitopss` — reads `clusters/**/teams/*.yaml`, creates one Application per team
- **New chart:** `base/config/onboarding/application-gitops` — provisions per team:
  - `<team>-gitops` namespace
  - ArgoCD CR with RBAC (team group gets admin role)
  - AppProject locked to team's repo + namespaces
  - RoleBinding for team admins
- Each team file is self-contained with `cluster.*` metadata (3 lines duplication required — git file generator can't merge with conf.yaml)

### 6. Separate team namespace provisioning (new feature)
- **New ApplicationSet:** `team-namespaces` — reads same team files, separate Application per team
- **New chart:** `base/config/onboarding/namespace-config` — provisions per namespace:
  - Namespace with `managed-by` label (SSA patch — won't take ownership of existing namespaces)
  - ResourceQuota based on t-shirt size
  - LimitRange based on t-shirt size
- Namespace creation is decoupled from ArgoCD instance creation — each syncs independently

### 7. T-shirt sizing for namespace resources
- Chart defaults (`base/config/onboarding/namespace-config/values.yaml`) define baseline sizes
- Environment-level overrides in dedicated `conf/<env>/namespace-sizes.yaml` files
- Cluster-level overrides in optional `clusters/<env>/<cluster>/namespace-sizes.yaml` (only specify fields to change)
- Sizing config is separated from cluster/environment conf.yaml into its own files
- `ignoreMissingValueFiles: true` on the team-namespaces ApplicationSet so cluster-level sizing files are optional
- Per-namespace overrides removed from template — sizing is controlled at environment and cluster level, not per-namespace
- ValueFiles chain: chart defaults → env conf → env namespace-sizes → cluster conf → cluster namespace-sizes → team file

## Current state

### Cluster conf structure
```
conf/<env>/
  conf.yaml              # environment-level config (registry, ingress, operators, etc.)
  namespace-sizes.yaml   # environment-level t-shirt size definitions
clusters/<env>/<cluster>/
  conf.yaml              # cluster metadata, configCharts, deployOperators, operators, managedCluster
  namespace-sizes.yaml   # cluster-level size overrides (optional, only changed fields)
  teams/
    team-alpha.yaml      # team definition with sized namespaces (no size overrides here)
```

### ApplicationSets (7 total)
| ApplicationSet | Generator source | Type label |
|---|---|---|
| cluster-operators | `conf.yaml` + `deployOperators` | operators |
| cluster-config | `conf.yaml` + `configCharts` | config |
| cluster-config-overlays | `conf.yaml` | config-overlay |
| cluster-import | `conf.yaml` + `managedCluster.deploy` | import |
| cluster-provisioning | `provision.yaml` | provisioning |
| application-gitopss | `teams/*.yaml` | team-gitops |
| team-namespaces | `teams/*.yaml` | team-namespaces |

### T-shirt sizes (dev vs prod)
| Size | Dev CPU (req/lim) | Prod CPU (req/lim) | Dev Pods | Prod Pods |
|---|---|---|---|---|
| small | 1/2 | 2/4 | 10 | 20 |
| medium | 4/8 | 8/16 | 20 | 40 |
| large | 8/16 | 16/32 | 50 | 100 |

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
- `RECOMMENDATION-conf-split.md` is in the repo — documents the design decisions and constraints around conf.yaml splitting
- `namespace-sizes.yaml` files are loaded via `ignoreMissingValueFiles: true` — if a cluster doesn't have one, it inherits from the environment

## Outstanding
- Team GitOps provisioning not yet tested end-to-end on a live cluster — awaiting app-of-apps sync
- No NetworkPolicy template in namespace-config yet — could inherit from project-request-template patterns
- Provisioning ApplicationSet untouched this session
- `conf/mgt/namespace-sizes.yaml` does not exist — create if mgt cluster needs team onboarding
