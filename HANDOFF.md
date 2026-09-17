# Session Handoff

**Modified:** 2026-09-17

## What changed this session

### Session changes (2026-09-17) — vSphere worker VM support in provisioning chart

#### Feature: `vsphereControlPlane.workers`
- Added `workers` subsection under `vsphereControlPlane` with `count`, `cpus`, `memoryMB`, `diskGB` (defaults to count: 0 — no behavior change for existing configs)
- govc script creates worker VMs named `<cluster>-vsphere-worker-<N>`, approves first N non-BMH agents as master, remainder as worker
- Ansible playbook updated with matching `Create vSphere worker VMs` task and split master/worker approval
- Both job templates (`govc` and `ansible`) pass `WORKER_COUNT`, `WORKER_CPUS`, `WORKER_MEMORY_MB`, `WORKER_DISK_GB` env vars
- All VM workers boot from the `-cp` InfraEnv ISO (same vSphere infrastructure)

#### Agent hostname assignment
- govc script and ansible playbook now set `spec.hostname` on each Agent CR during approval (DHCP does not always set hostnames on discovery-booted VMs)
- Masters get `<cluster>-master-<N>`, VM workers get `<cluster>-vsphere-worker-<N>` — matching the VM names in vSphere

#### Files changed
- `charts/cluster-provisioning/openshift-provisioning/values.yaml`
- `charts/cluster-provisioning/openshift-provisioning/files/vsphere-cp-govc.sh`
- `charts/cluster-provisioning/openshift-provisioning/files/vsphere-cp-playbook.yml`
- `charts/cluster-provisioning/openshift-provisioning/templates/job-vsphere-cp-govc.yaml`
- `charts/cluster-provisioning/openshift-provisioning/templates/job-vsphere-cp-ansible.yaml`
- `docs/reference/provision.yaml`

### Session changes (2026-09-17) — Quay chart: teams, repos, robot permissions, repo defaults

#### Config bundle enhancements
- `CREATE_PRIVATE_REPO_ON_PUSH` — repos created via push default to private
- `FEATURE_RESTRICTED_USERS` + `RESTRICTED_USERS_WHITELIST` — restricts who can create repos/orgs to superusers + whitelist

#### Init job enhancements (execution order: orgs → teams → repos → robots)
- **Teams**: creates teams inside orgs with role (member/creator/admin), optional `syncGroup` to bind team membership to OIDC/LDAP group via team sync API
- **Repositories**: pre-creates repos with explicit visibility (private by default)
- **Robot permissions**: each robot account can now have a `permissions` list scoping it to specific repos with a role (read/write/admin)

#### Values additions
- `config.createPrivateOnPush` (default: true)
- `config.restrictedUsers.include` / `config.restrictedUsers.whitelist`
- `init.teams[].org/name/role/description/syncGroup`
- `init.repositories[].org/name/visibility/description`
- `init.robotAccounts[].permissions[].repo/role`

#### Hub config updated
- Added 4 teams: platform/admins (admin, syncGroup: admins), platform/devs (member, syncGroup: users), team-alpha/devs, team-beta/devs
- Added repository: platform/base-images (private)
- Scoped robot permissions: cicd→base-images(write), pull→base-images(read)
- Enabled restricted users with whitelist [quayadmin, admin]

#### Documentation
- Created `docs/day2-cluster-config/quay-registry.md` — setup guide covering auth-type-at-first-boot constraint, org-per-team layout, team sync with OIDC groups, robot scoping, repo defaults, init job execution order, Keycloak client registration
- Updated `docs/day2-cluster-config/README.md` — cross-reference to Quay setup guide
- Updated `docs/reference/operator-instances.yaml` — all new fields with inline comments

### Session changes (2026-09-17) — Cluster Observability Operator instance chart

#### New chart: `charts/operator-instances/cluster-observability/`
- Full COO instance chart covering all 3 CRD families:
  - **UIPlugin** (5 types): Dashboards, TroubleshootingPanel, DistributedTracing, Logging, Monitoring
  - **MonitoringStack**: per-namespace Prometheus + Alertmanager for multi-tenant monitoring
  - **ThanosQuerier**: federated query across MonitoringStack instances
- UIPlugin CRs are cluster-scoped; MonitoringStack/ThanosQuerier are namespace-scoped
- UIPlugin fields match CRD schema verified from live cluster:
  - `logging`: lokiStack.name, logsLimit, timeout, schema (viaq/otel/select)
  - `monitoring`: acm (alertmanager + thanosQuerier proxy), clusterHealthAnalyzer, perses
  - `distributedTracing`: timeout only (auto-discovers TempoStack)
- MonitoringStack supports: namespaceSelector, resourceSelector, resources, prometheusConfig (retention, replicas, PVC, remoteWrite), alertmanagerConfig, tolerations
- ThanosQuerier supports: selector + namespaceSelector for MonitoringStack federation
- Template tests: 52/52 pass
- E2E tests: 8/8 pass on hub — operator CSV Succeeded, all 3 CRDs exist, 2 UIPlugins Available=True and registered as console plugins

#### Hub cluster config updated
- Added `- chart: cluster-observability` to `operatorInstanceCharts` in `clusters/mgt/acm-hub/conf.yaml`
- Enabled `uiPlugins.dashboards` and `uiPlugins.troubleshootingPanel` in `clusters/mgt/acm-hub/operator-instances.yaml`

#### Operator-deployment default fixed
- Changed `cluster-observability` default channel from `change-me` to `stable` in `charts/operator-deployment/values.yaml`

#### Reference docs updated
- Added `cluster-observability` to `docs/reference/conf.yaml` under Recommended tier
- Added full `uiPlugins`, `monitoringStacks`, and `thanosQueriers` sections to `docs/reference/operator-instances.yaml`

### Session changes (2026-09-17) — Tier reclassification across all reference + day2 files

#### Tier review completed for all 3 categories
- Reviewed every chart/operator across platformCharts (31), operatorInstanceCharts (28), and operator-deployment (35) with user input on tier placement
- Final tier assignments:
  - **platformCharts** — Critical: 9 (tls-certificates, openshift-apiserver, openshift-ingress, openshift-proxy, openshift-oauth, openshift-image-registry, global-pull-secrets, openshift-machine-config, acm-managed-cluster), Recommended: 13 (etcd-backup, etcd-defrag, user-workload-monitoring, project-request-template, machine-health-checks, image-pruner, openshift-console, prometheus-rules, alertmanager-config, rbac, openshift-build, openshift-group-sync, acm-policies), Nice to Have: 9
  - **operatorInstanceCharts** — Critical: 1 (openshift-gitops-instance), Recommended: 8 (acs-secured-cluster, compliance-scans, acm-multiclusterhub, acm-observability, acs-central, logging-lokistack, odf-storagecluster, local-storage-volumes), Nice to Have: 23 (includes cluster-observability)
  - **operator-deployment** — Critical: 2 (openshift-gitops, compliance-operator), Recommended: 6 (ACS, ACM, logging, loki, ODF, local-storage), Nice to Have: 27

#### Cross-file consistency fix
- Moved `cluster-observability` from Recommended to Nice to Have in `docs/reference/conf.yaml` and `docs/reference/operator-instances.yaml` to match user's tier decision and `docs/day2-cluster-config/README.md`

#### Files updated
- `docs/reference/conf.yaml` — reorganized platformCharts and operatorInstanceCharts into tier sections
- `docs/reference/platform-config.yaml` — fixed orphaned section dividers, charts properly grouped under Critical/Recommended/Nice to Have headers
- `docs/reference/operator-deployment.yaml` — reorganized all 35 operators into tier sections, removed duplicates
- `docs/reference/operator-instances.yaml` — reorganized all 31 chart blocks into tier sections, fixed duplicate section headers
- `docs/reference/README.md` — updated tier description table to reflect final classifications
- `docs/day2-cluster-config/README.md` — updated all tier tables (Critical/Recommended/Nice to Have) and cluster examples (Minimal, Full recommended)

### Session changes (2026-09-17) — Reference values files + documentation restructure

#### Reference values files created in `docs/reference/`
- Created fully-commented example files for defining a cluster from scratch:
  - `conf.yaml` — cluster identity, all 31 platformCharts + 28 operatorInstanceCharts listed, deploy toggles, team onboarding
  - `platform-config.yaml` — all 31 platform-config charts with every field documented, organized by tier (Critical/Recommended/Nice to Have)
  - `operator-instances.yaml` — all operator instance charts with full CR configuration examples (ACS, Quay, Keycloak OIDC, compliance, ODF, service mesh, etc.)
  - `operator-deployment.yaml` — all available OLM operators with field reference (include, namespace, channel, source, clusterScoped, etc.)
  - `provision.yaml` — all 4 provisioning platforms (AWS IPI, vSphere IPI, baremetal agent-based, platform-none) plus cross-platform options (proxy, NTP, networking, disconnected registry)
  - `README.md` — index with quick-start copy workflow, file descriptions, values precedence, placeholder conventions
- Files use placeholder values (YOUR_*, CHANGEME_*, example.com) — already sanitized by design, no sanitize.sh additions needed
- Located in `docs/reference/` (not `clusters/`) to stay out of ApplicationSet generators

#### Documentation restructure

#### Cluster provisioning docs split into per-platform guides
- Replaced single `docs/cluster-provisioning.md` and `docs/Baremetal.md` with `docs/cluster-provisioning/` directory:
  - `README.md` — overview, provisioning models (IPI vs agent-based), cross-platform features (proxy, NTP, ignition, custom manifests, trust bundle, disconnected registry, FIPS), ApplicationSet mechanics, cluster definition files
  - `aws.md` — AWS IPI provisioning (instance types, AZs, root volumes)
  - `vsphere.md` — vSphere IPI provisioning (vCenter config, VM sizing, field reference)
  - `baremetal.md` — agent-based baremetal (BMC/Redfish, NMState static networking, dual-stack, per-host BMC credentials)
  - `platform-none.md` — agent-based platform:none (userManagedNetworking, sushy-EC2 emulator)
  - `vsphere-control-plane.md` — hybrid mode (vSphere CP VMs + baremetal workers, split InfraEnvs, govc Job, vcsim simulator)
- Removed old files: `docs/cluster-provisioning.md`, `docs/Baremetal.md`
- Updated cross-references in: `README.md`, `docs/cluster-configuration.md`, `.github/scripts/sanitize.sh` (public README template)

#### Cluster configuration docs split into per-topic guides
- Replaced single `docs/cluster-configuration.md` with `docs/cluster-configuration/` directory:
  - `README.md` — overview, 8 ApplicationSets table, chart categories summary, adding/removing charts, preserveResourcesOnDeletion
  - `applicationsets.md` — matrix generator with elementsYaml, boolean gates, team-driven generators
  - `chart-categories.md` — platform-config (31 charts), operator-instances (31 charts), operator-deployment, onboarding with full chart listings
  - `values-precedence.md` — values chain, ignoreMissingValueFiles, include pattern, environment-level defaults
  - `conf-yaml.md` — conf.yaml structure, field reference table, cluster directory layout
- Removed old file: `docs/cluster-configuration.md`
- Updated cross-references in: `README.md`, `docs/cluster-provisioning/README.md`, `.github/scripts/sanitize.sh` (public README template)

#### Day 2 cluster config docs split into checklist + setup guides
- Replaced single `docs/day2-cluster-config.md` with `docs/day2-cluster-config/` directory:
  - `README.md` — slim checklist: tier tables (Critical/Recommended/Nice to Have), cluster examples (minimal, full recommended, hub)
  - `acs-setup.md` — ACS secured cluster setup, resource tuning for small clusters, init bundle secrets and timing
  - `oauth-keycloak.md` — Keycloak OIDC registration, client secret, chart values, pitfalls (ArgoCD+Groups, orphaned identities, issuer URL, hub TLS)
  - `compliance.md` — compliance operator setup, TailoredProfiles
- Removed old file: `docs/day2-cluster-config.md`
- Moved `docs/letsencrypt-dns01-setup.md` into `docs/day2-cluster-config/letsencrypt-dns01-setup.md` — colocated with the cert-manager-certs use case
- Updated cross-references in: `README.md`, `docs/cluster-configuration/README.md`, `.github/scripts/sanitize.sh` (public README template)

#### Stale files removed
- Removed `docs/architecture-operator-cr-coupling.md` — completed decision doc, context in git history
- Removed `scripts/COMPLIANCE-REPORT-NEXT.md` — future work planning, should be a GitHub issue
- Removed AI scripts from `scripts/`: `ai-common.sh`, `ai-fix`, `ai-implement`, `ai-plan`, `ai-research`, `ai-review`, `ai-run`, `bootstrap-ai-dev.sh`
- Added AI scripts to sanitize.sh section 1 (non-release file removal) as a safety net

### Session changes (2026-09-16) — vSphere control plane automation for mixed clusters

#### vSphere control plane automation (agent-based mixed cluster: vSphere VMs + bare metal workers)
- Added `vsphereControlPlane` section to `values.yaml` — toggles vSphere VM creation for control plane nodes in agent-based provisioning (platform `baremetal` or `none`)
- Two automation backends selectable via `vsphereControlPlane.automation`: `govc` (shell script) or `ansible` (Ansible playbook)
- **govc mode**: Downloads govc binary, waits for InfraEnv ISO, uploads to vCenter datastore, creates VMs with cdrom boot, waits for non-BMH agents, approves as masters
- **ansible mode**: Uses `community.vmware` collection for VM lifecycle, `kubernetes.core` for agent approval — same flow as govc but declarative
- Files in `files/` directory (embedded via `.Files.Get` to avoid Helm/Jinja2 delimiter conflicts):
  - `vsphere-cp-govc.sh` — govc automation script
  - `vsphere-cp-entrypoint.sh`, `vsphere-cp-playbook.yml`, `vsphere-cp-requirements.yml` — ansible automation
- 6 new templates:
  - `rbac-vsphere-cp.yaml` — SA + Role + RoleBinding (wave 6), grants get/list/watch on infraenvs + get/list/watch/patch/update on agents
  - `secret-vsphere-cp-creds.yaml` — vCenter credentials (wave 6)
  - `configmap-vsphere-cp-govc.yaml` — govc script (wave 7, govc mode only)
  - `configmap-vsphere-cp-ansible.yaml` — ansible scripts (wave 7, ansible mode only)
  - `job-vsphere-cp-govc.yaml` — govc Job (wave 9, Replace=true for re-syncs)
  - `job-vsphere-cp-ansible.yaml` — ansible Job (wave 9, Replace=true for re-syncs)
- All templates guarded by `provision.include && isAgent && vsphereControlPlane.enabled` (+ automation mode for ConfigMap/Job)
- **vcsim simulator toggle** (`vsphereControlPlane.simulator.enabled`): deploys govmomi vcsim as Deployment+Service in the cluster namespace for testing without a real vCenter
  - `deployment-vsphere-cp-vcsim.yaml` — vcsim Deployment + Service (wave 7), same guard + `simulator.enabled`
  - Job templates conditionally set `VCENTER` env to `{cluster}-vcsim` (simulator) or real vCenter URL
  - vcsim listens on port 443 to match standard vCenter HTTPS — no port changes needed in scripts
- **Dual InfraEnv for mixed clusters**: When `vsphereControlPlane.enabled`, creates separate InfraEnv resources for CP (`{name}-cp`) and workers (`{name}-workers`). vSphere VMs and bare metal servers need different discovery ISOs due to different NIC names (vmxnet3 vs physical), boot flows, and network configs. Each InfraEnv uses `nmStateConfigLabelSelector` with `infraenv:` labels instead of `cluster-name:`. BareMetalHost and NMStateConfig resources use the `-workers` InfraEnv. govc/ansible Jobs receive `INFRAENV_NAME` env var (`{name}-cp`) with fallback `${INFRAENV_NAME:-${CLUSTER_NAME}}` for backward compat. CP InfraEnv supports optional `vsphereControlPlane.ignitionConfigOverride` (falls back to global). Fully backward compatible — single InfraEnv when `vsphereControlPlane.enabled: false`.
- Template tests expanded from 97 to 160 assertions — covers govc mode, ansible mode, simulator mode, exclusion on disabled/non-agent platforms, dual InfraEnv for mixed clusters, and backward compatibility with single InfraEnv

### Session changes (2026-09-16) — Provisioning chart sync fixes + tests

#### 1. ArgoCD sync fixes for provisioning app (3 separate issues)
- **spec.installed drift**: Hive admission webhook rejects `installed: false` on already-installed clusters. Fixed by adding `ignoreDifferences` for `/spec/installed` on ClusterDeployment in the ApplicationSet + `RespectIgnoreDifferences=true` syncOption
- **agentLabelSelector perpetual sync loop**: The assisted-service controller strips `spec.agentLabelSelector` and manages it in `status.agentLabelSelector`. Fixed by removing it from the InfraEnv template
- **cluster-platform label drift**: Hive normalizes `hive.openshift.io/cluster-platform` to `agent-baremetal` for agent-based platforms. Added `cluster.platformLabel` helper in `_helpers.tpl` that maps `baremetal`/`none` → `agent-baremetal`

#### 2. Chart test coverage
- Created `charts/cluster-provisioning/openshift-provisioning/tests/template-test.sh` — 97 assertions covering all 4 platforms (vsphere, aws, baremetal, none), conditional features (NTP, proxy, FIPS, NMState, ignition, custom manifests, trust bundles), sync wave ordering, platform label normalization, and agentLabelSelector removal
- Created `charts/cluster-provisioning/openshift-provisioning/tests/e2e-test.sh` — live cluster validation via `oc` (namespace, ClusterDeployment, ManagedCluster, agent/IPI resources, ArgoCD sync status)

### Session changes (2026-09-16) — Quay registry chart restructure

#### Quay chart value restructuring
- Consolidated 3 top-level keys (`quayRegistry`, `quayBridge`, `quayKeycloak`) into single `quay:` root with sub-sections
- Everything togglable via `include` flags following existing repo pattern
- Value hierarchy: `quayRegistry.config`, `quayRegistry.components`, `quayRegistry.scheduling`, `quayRegistry.customTls`, `quayRegistry.externalDatabase`, `quayRegistry.externalStorage`, `quayRegistry.oidc`, `quayRegistry.bridge`, `quayRegistry.init`

#### Component overrides (11 components)
- All 11 QuayRegistry components togglable via `managed: true/false`
- Components with workloads (quay, clair, clairpostgres, postgres, redis, mirror) get `overrides:` block with replicas, resources, affinity, tolerations
- postgres and clairpostgres support `volumeSize`
- HPA, route, monitoring, TLS are toggle-only (no resource overrides)

#### Infra node scheduling (`quayRegistry.scheduling`)
- Single `scheduling.include` flag injects node affinity + tolerations into all managed component overrides
- Default: `node-role.kubernetes.io/infra` with NoSchedule toleration

#### External integrations (auto-toggle managed components)
- `quayRegistry.externalDatabase.include` — renders `DB_URI` in config bundle, auto-sets postgres component `managed: false`
- `quayRegistry.externalStorage.include` — renders `DISTRIBUTED_STORAGE_CONFIG`, auto-sets objectstorage `managed: false`
- `quayRegistry.customTls.include` — adds `ssl.cert`/`ssl.key` to config bundle secret, auto-sets TLS component `managed: false`
- `quayRegistry.oidc.include` — renders `{PROVIDER}_LOGIN_CONFIG` block (provider name uppercased), auto-disables `FEATURE_DIRECT_LOGIN`

#### Config bundle features
- All feature flags driven by values: quotas, auto-prune, garbage collection, rate limits, team syncing, action log rotation, repo mirror
- `FEATURE_REPO_MIRROR: true` auto-set when mirror component is managed
- Server hostname + preferred URL scheme rendered when `serverHostname` is set
- Fixed scientific notation for `DEFAULT_SYSTEM_REJECT_QUOTA_BYTES` — uses `| int64` filter

#### Quay Bridge (`quayRegistry.bridge`)
- `quayHostname` auto-derived from `quayRegistry.name`, `quayRegistry.namespace`, and `cluster.baseDomain`
- Denylist rendered via `toYaml` from values list (was ~60 hardcoded lines)
- OAuth token stored in separate Secret (not inline)

#### Init Job (`quayRegistry.init`) — new template
- PostSync hook creates organizations and robot accounts via Quay REST API
- Waits for `/health/instance` endpoint before running
- OAuth token stored in `quay-init-token` Secret, injected via env var
- Configurable org list (`organizations[].name/email`) and robot list (`robotAccounts[].org/name/description`)

#### Hub cluster config updated
- `clusters/mgt/acm-hub/operator-instances.yaml` migrated from old 3-key structure (`quayRegistry`, `quayBridge`, `quayKeycloak`) to consolidated `quayRegistry:` with nested sub-sections

### Session changes (2026-09-16) — RBAC chart + external-secrets chart + preserve docs

#### 0. RBAC management chart
- Created `charts/platform-config/rbac/` — centralized RBAC management for platform-level resources
- Four resource types: ClusterRoles, Roles, ClusterRoleBindings, RoleBindings
- Each section has top-level `include` toggle + per-item `include` (storage-classes pattern)
- Supports all subject types: Group, User, ServiceAccount (apiGroup auto-set by kind)
- RoleBindings support both `clusterRole` and `role` references (mutually exclusive, sets roleRef.kind accordingly)
- Scoped to platform-level RBAC only — app-specific RBAC belongs in the app chart, OAuth groupRBAC stays in openshift-oauth
- Deploy by adding `- chart: rbac` to `platformCharts` in conf.yaml

#### 1. External secrets instance chart (scoped to platform secrets)
- Created `charts/operator-instances/external-secrets/` — templates ExternalSecret CRs from a `secrets` list in values
- Each entry specifies name, namespace, type, vault path, and property mappings
- Defaults to the `vault` ClusterSecretStore (from vault-server chart); per-secret override supported
- Scoped to platform/cluster-wide secrets (ingress certs, OIDC, pull secrets) — app-specific ExternalSecrets belong in the app chart
- Requires: `external-secrets-operator` deployed, `ClusterSecretStore` created (vault-server chart), Vault KV paths populated

#### 2. preserveResourcesOnDeletion docs
- Created `docs/ai-dev/applicationset-preserve-resources.md` — explains AppSet-level vs App-level flags, interaction matrix, and migration guide for adopting existing resources
- Added gotcha to HANDOFF.md Gotchas section

### Session changes (2026-09-16) — aws-test additional operators, teams, compliance

#### 5. ACS Secured Cluster on aws-test
- Added `acs-secured-cluster` to `operatorInstanceCharts` in conf.yaml
- ACS operator already deployed at env level; env-level `securedCluster: include: true` with `secretMode: "generate"` handles config
- Added `sensor.resources` template to SecuredCluster CR and chart values — enables per-cluster CPU/memory overrides
- aws-test: sensor reduced to 500m CPU, scannerV4 disabled, admission control disabled, slim collectors
- Hub Central: reduced from 1500m to 500m CPU, scanner replicas 2→1, scannerV4 replicas 3→1
- **ACS 4.11 init bundle gotcha**: Do NOT manually create `tls-cert-*` secrets — the operator creates them internally from legacy init bundle secrets. Partial `tls-cert-*` secrets trigger a CA consistency check that blocks reconciliation. Fix: delete all `tls-cert-*` secrets and restart the operator pod.

#### 6. Compliance operator + scans on aws-test
- Added `compliance-operator` to cluster-level `operator-deployment.yaml` (channel: `stable`)
- Added `compliance-scans` to `operatorInstanceCharts` in conf.yaml
- Enabled `scanSetting` and `scanSettingBinding` in `operator-instances.yaml` (STIG profiles, daily scans)
- **Fixed**: ScanSetting and ScanSettingBinding templates had fields under `spec:` but the compliance CRDs use root-level fields — scans never ran because profiles weren't parsed
- Added TailoredProfile support: `tailoredProfiles` list in values.yaml with `disableRules`, `enableRules`, `setValues` per profile; template iterates the list with `include` toggle per entry

#### 9. Console CR fix
- Console chart rendered empty `customization: null` and `developerCatalog.types.state: Enabled` causing perpetual OutOfSync
- Fixed to render `spec: {}` when no customization is configured
- Same pattern as the proxy chart `spec: Required value` fix

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
- **Cluster installed**: OpenShift 4.22.13, all 34 COs Available, 3 nodes Ready
- ArgoCD provision app: Healthy (successfully synced)
- ArgoCD import app: removed (`deployImport: false`)
- Sushy emulator: Running 1/1 in `sushy-ec2` namespace
- AgentClusterInstall: `adding-hosts` (100% complete)
- All 3 agents: Done (100%)
- Kubeconfig: `oc get secret aws-none-prod-admin-kubeconfig -n aws-none-prod -o jsonpath='{.data.kubeconfig}' | base64 -d`
- AWS infra changes persisted from Run 3: cross-zone LB enabled on both NLBs, api-int DNS pointing to private IPs

## Previous session changes

### 1. Values refactoring — flattened nesting and auto-derived URLs
- **acs-central**: Moved `central.initBundle` → top-level `initBundle`, `central.consoleLink` → top-level `centralConsoleLink`; `centralUrl` auto-derived from `cluster.baseDomain`
- **acs-secured-cluster**: `centralEndpoint` auto-derived from `cluster.baseDomain` (explicit override still required for managed clusters pointing to remote Central)
- **quay-registry**: Consolidated `quayRegistry`, `quayBridge`, `quayKeycloak` → single `quay:` root; added external DB/storage/TLS integrations, infra scheduling, OIDC, init job; all components togglable
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
- `preserveResourcesOnDeletion: true` is set at the AppSet level on all 8 ApplicationSets — if a generator stops matching, the Application is removed but cluster-side resources survive. The Application template level flag is **not** set, so a direct `oc delete` of an Application will cascade-delete its managed resources. See `docs/ai-dev/applicationset-preserve-resources.md` for the full interaction matrix and migration guide.
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
| rbac | `./tests/e2e-test.sh [values-file]` |
| etcd-defrag | `./tests/e2e-test.sh` |
| project-request-template | `./tests/e2e-test.sh` |
| openshift-marketplace | `./tests/e2e-test.sh` |
| application-gitops | `./tests/e2e-test.sh <team-name>` |
| namespace-config | `./tests/e2e-test.sh <team-name> <environment>` |
| openshift-provisioning | `./tests/template-test.sh` (160 assertions), `./tests/e2e-test.sh <cluster-name>` |

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
- **aws-none-prod**: Cluster installed successfully (Run 4). Next steps: enable `deployImport` to register with ACM hub, configure day2 platform charts
- No NetworkPolicy template in namespace-config yet
- AAP controller not deploying on any cluster — needs investigation
- Prod cluster (cluster-m6tk9) e2e tests not yet run
- etcd-backup/etcd-defrag CronJobs need verification after they fire
