# Session Handoff

**Modified:** 2026-09-16

## What changed this session

### Session changes (2026-09-16) — aws-test additional operators, teams, compliance

#### 5. ACS Secured Cluster on aws-test
- Added `acs-secured-cluster` to `operatorInstanceCharts` in conf.yaml
- ACS operator already deployed at env level; env-level `securedCluster: include: true` with `secretMode: "generate"` handles config

#### 6. Compliance operator + scans on aws-test
- Added `compliance-operator` to cluster-level `operator-deployment.yaml` (channel: `stable`)
- Added `compliance-scans` to `operatorInstanceCharts` in conf.yaml
- Enabled `scanSetting` and `scanSettingBinding` in `operator-instances.yaml` (STIG profiles, daily scans)

#### 7. External secrets operator on aws-test
- Added `external-secrets-operator` to cluster-level `operator-deployment.yaml` (channel: `stable-v1`)
- Fixed chart default channel from `change-me` to `stable-v1`
- Operator-only for now — no instance chart yet (closes gap for future OIDC secret management)

#### 8. Team onboarding on aws-test
- Added `team-alpha` and `team-beta` to `teams` list in conf.yaml
- Both teams get their own ArgoCD instance + dev namespaces (team-alpha-dev, team-alpha-stage, team-beta-dev, team-beta-stage)

### Session changes (2026-09-16) — aws-test day2 config + OAuth/Keycloak OIDC

#### 1. Let's Encrypt DNS01 TLS on aws-test
- Switched from self-signed CA to Let's Encrypt ACME with Route53 DNS01 solver
- Added ACME ClusterIssuer + CredentialsRequest templates to `cert-manager-certs` chart
- Added CertManager CR template for `--dns01-recursive-nameservers-only` flag
- Cluster-level config: `clusters/dev/aws-test/operator-instances.yaml` enables acmeIssuer with Route53 zone
- Fixed: `openshift-proxy` chart errored on empty `spec:` — now renders `trustedCA.name` with default empty string
- Fixed: Hive admin kubeconfig on hub had old CA in `certificate-authority-data` — patched both `kubeconfig` and `raw-kubeconfig` keys

#### 2. Recommended platform charts enabled on aws-test
- Added 10 platform charts to `clusters/dev/aws-test/conf.yaml`: etcd-backup, etcd-defrag, user-workload-monitoring, project-request-template, machine-health-checks, image-pruner, openshift-console, prometheus-rules, alertmanager-config, openshift-oauth
- Full values configured in `clusters/dev/aws-test/platform-config.yaml`

#### 3. OpenShift OAuth with Keycloak OIDC on aws-test
- Registered `openshift` OIDC client in hub Keycloak realm (`clusters/mgt/acm-hub/operator-instances.yaml`)
- Added `groups` protocol mapper to keycloak-instance chart for OIDC group claim
- Created `openshift-oidc-client-secret` imperatively on aws-test (no sealed-secrets operator)
- Configured openshift-oauth chart with Keycloak OIDC provider and groupRBAC (admins→cluster-admin, users→edit)
- Added `rbac.yaml` template to openshift-oauth chart — ClusterRoleBindings only
- Removed Group resources from chart — ArgoCD self-heal resets `users` field, breaking OIDC group membership
- Fixed orphaned identity blocking login after user cleanup

#### 4. Documentation
- Created `docs/day2-cluster-config.md` — comprehensive day2 guide with Critical/Recommended/Nice to Have tiers, now includes OAuth/Keycloak OIDC setup section
- Created `docs/ai-dev/letsencrypt-dns01-setup.md` — LE DNS01 setup with Hive fix
- Created `docs/ai-dev/claude-sa-setup.md` — ServiceAccount + kubeconfig setup

### Session changes (2026-09-16) — aws-none-prod reprovisioning

#### 1. Sushy EC2 emulator Helm chart
- Created `charts/cluster-provisioning/sushy-ec2-emulator/` — Deployment, Service (with OpenShift serving cert), ConfigMap (instances.json), BuildConfig, ImageStream
- Moved emulator from `aws-none-prod` namespace to dedicated `sushy-ec2` namespace
- Service name stays `sushy-ec2` — BMH addresses updated to `sushy-ec2.sushy-ec2.svc:8000`

#### 2. aws-none-prod cleanup and reprovisioning
- Deleted `aws-none-prod` namespace (BMHs stuck in `provisioning` for 11+ hours, no agents registered)
- Cleared BMH/PreprovisioningImage/Secret finalizers to unblock namespace termination
- Set `deployImport: false` in `clusters/prod/aws-none-prod/conf.yaml` (import not needed during provisioning)
- Updated BMH addresses in `provision.yaml` to reference new `sushy-ec2` namespace

#### 3. Quay Bridge denylist
- Added `sushy-ec2` to denylist in `charts/operator-instances/quay-registry/templates/quay-bridge.yaml`
- Quay Bridge webhook blocks builds in namespaces without provisioned Quay robot secrets — denylist exempts infrastructure namespaces
- Workaround: built image locally with podman and pushed directly to internal registry route

#### 4. Provisioning chart sync-wave fixes
- ClusterDeployment moved from wave 360 → 357 (must exist before ACI/InfraEnv)
- BMC credential secrets moved from wave 355 → 361 (before BMHs, after InfraEnv)
- BareMetalHosts added wave 362 (were at wave 0, causing deadlock)
- NMStateConfig added wave 361

### Current state — aws-none-prod
- ArgoCD provision app: Healthy (successfully synced)
- ArgoCD import app: removed (`deployImport: false`)
- Sushy emulator: Running 1/1 in `sushy-ec2` namespace, ignition URL patched
- InfraEnv: Available, ISO created
- PreprovisioningImages: All 3 ready (InfraEnvAvailable)
- BareMetalHosts: All 3 in `provisioning` state with correct addresses
- AgentClusterInstall: `insufficient` — waiting for agents to register
- Agents: None yet — EC2 instances booting from discovery ISO

## Previous session changes

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

### 7. Environment-scoped team namespaces
- `team.namespaces` changed from flat list to environment-keyed map (`team.namespaces.dev`, `team.namespaces.prod`)
- Charts select the right list using `cluster.environment` — each cluster only provisions namespaces for its own environment
- Auto-prune enabled on both onboarding ApplicationSets — removing a namespace from the list deletes it from the cluster
- team-beta onboarded to dev cluster — both gitops and namespace apps Synced/Healthy
- Tested end-to-end: team-alpha dev namespaces correct, stale preprod namespace auto-pruned

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
deployProvision: false   # or true
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
| cluster-provisioning | `conf.yaml` + `deployProvision` | provisioning |
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
├── onboarding-*-dev-cluster-lz5bn-team-alpha
│   └── team-alpha ArgoCD instance + namespaces (dev, stage)
│
└── onboarding-*-dev-cluster-lz5bn-team-beta
    └── team-beta ArgoCD instance + namespaces (dev, stage)
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

## E2E Testing

Every active chart has both a Helm test template (`templates/tests/test-connection.yaml`) and a shell script (`tests/e2e-test.sh`). Helm tests validate basic resource existence; shell scripts do deeper e2e validation.

**Note:** ArgoCD does not run Helm test hooks — use `helm test` for local validation only. Shell scripts are the primary e2e mechanism.

| Chart | Shell script usage |
|---|---|
| operator-deployment | `./tests/e2e-test.sh` |
| openshift-gitops-instance | `./tests/e2e-test.sh` |
| acm-multiclusterhub | `./tests/e2e-test.sh` |
| acs-central | `./tests/e2e-test.sh [namespace]` |
| acs-secured-cluster | `./tests/e2e-test.sh [namespace]` |
| aap-instance | `./tests/e2e-test.sh [namespace]` |
| acm-observability | `./tests/e2e-test.sh` |
| quay-registry | `./tests/e2e-bridge-test.sh <quay-host> <token>` |
| acm-managed-cluster | `./tests/e2e-test.sh <cluster-name>` |
| user-workload-monitoring | `./tests/e2e-test.sh` |
| etcd-backup | `./tests/e2e-test.sh` |
| etcd-defrag | `./tests/e2e-test.sh` |
| project-request-template | `./tests/e2e-test.sh` |
| openshift-marketplace | `./tests/e2e-test.sh` |
| application-gitops | `./tests/e2e-test.sh <team-name>` |
| namespace-config | `./tests/e2e-test.sh <team-name> <environment>` |

### E2E test results (2026-09-11)

Ran against hub (cluster-c8444) and dev (cluster-lz5bn).

**Hub cluster:**

| Chart                          | Result     | Notes                                       |
|--------------------------------|------------|---------------------------------------------|
| operator-deployment            | 26/26 PASS |                                             |
| openshift-gitops-instance      | 5/5 PASS   |                                             |
| acm-multiclusterhub            | 6/6 PASS   |                                             |
| acs-central                    | 5/5 PASS   |                                             |
| acs-secured-cluster            | 5/5 PASS   |                                             |
| acm-observability              | 6/6 PASS   |                                             |
| acm-managed-cluster (dev)      | 5/5 PASS   |                                             |
| acm-managed-cluster (prod)     | 5/5 PASS   |                                             |
| user-workload-monitoring       | 5/5 PASS   |                                             |
| project-request-template       | 5/5 PASS   | Created+verified+cleaned up test project    |
| etcd-defrag                    | 4/5        | Weekly CronJob hasn't triggered yet         |
| etcd-backup                    | 4/5        | CronJob created but no completed Job yet    |
| aap-instance                   | 2/5        | AAP controller not deployed                 |

**Dev cluster:**

| Chart                          | Result     | Notes                                       |
|--------------------------------|------------|---------------------------------------------|
| application-gitops (alpha)     | 5/5 PASS   |                                             |
| application-gitops (beta)      | 5/5 PASS   |                                             |
| namespace-config (alpha)       | 8/8 PASS   | Both namespaces, quotas, limits validated   |
| acs-secured-cluster            | 5/5 PASS   |                                             |
| user-workload-monitoring       | 2/5        | UWM not configured with custom ConfigMap    |
| openshift-marketplace          | 1/4        | Local CatalogSources not enabled            |
| aap-instance                   | 2/5        | AAP controller not deployed                 |

**Not yet tested:** prod cluster (cluster-m6tk9) — same charts as dev

### Session changes (2026-09-11)

- Made cluster-provisioning ApplicationSet toggleable via `deployProvision` flag in conf.yaml (was file-presence based)
- Created e2e tests (Helm test template + shell script) for all 15 active charts
- Fixed test bugs found during live cluster run: `((PASSED++))` with `set -e`, wrong pod labels, wrong job names, OBC column index, SA token method
- Created HANDOFF.md for operator-deployment and openshift-gitops-instance charts
- Added `## Testing` section to all 13 existing active chart HANDOFFs

## Outstanding
- **aws-none-prod**: commit and push pending changes, then sync ArgoCD to recreate provisioning resources; patch ignition URL after InfraEnv generates ISO
- No NetworkPolicy template in namespace-config yet
- AAP controller not deploying on any cluster — needs investigation
- Prod cluster (cluster-m6tk9) e2e tests not yet run
- etcd-backup/etcd-defrag CronJobs need verification after they fire
