# Day 2 Cluster Configuration Guide

What to enable on a new managed cluster after provisioning. Everything is deployed via GitOps — add the chart to `conf.yaml`, set values in `platform-config.yaml` / `operator-instances.yaml` / `operator-deployment.yaml`, push to git, and ArgoCD syncs it.

The configuration is layered: chart defaults → `env/<env>/` overrides → `clusters/<env>/<cluster>/` overrides. Most items below only need a few lines in the cluster-level files.

---

## Critical — enable on every cluster

These form the baseline platform configuration. A cluster without them is missing security controls, proper TLS, or observability.

### Operators

| Operator | Channel | What it does | Notes |
|----------|---------|-------------|-------|
| `openshift-gitops` | `gitops-1.21` | ArgoCD for GitOps delivery | Already set at `env/dev/` and `env/prod/` level |
| `cert-manager` | `stable-v1` | Certificate lifecycle management | Required for TLS automation |
| `advanced-cluster-security` | `stable` | Container security (StackRox) | Already set at env level; ACS Central runs on hub only |

### Operator Instances

| Chart | What it does | Prerequisites | Config needed |
|-------|-------------|---------------|---------------|
| `cert-manager-certs` | ClusterIssuers (self-signed CA or Let's Encrypt ACME) | cert-manager operator | `operator-instances.yaml` — enable acmeIssuer or caIssuer. For LE: Route53 zone ID, region, email. See [letsencrypt-dns01-setup.md](letsencrypt-dns01-setup.md) |
| `acs-secured-cluster` | Connects cluster to ACS Central on the hub | ACS operator, Central endpoint | Set at env level. `centralEndpoint` must point to hub's ACS Central route. See [ACS setup](#acs-secured-cluster-setup) below |

### ACS Secured Cluster setup

The `acs-secured-cluster` chart deploys a SecuredCluster CR, an init bundle generation job, and the necessary RBAC. The env-level config (`env/dev/operator-instances.yaml`) handles most defaults including `secretMode: "generate"` and `centralEndpoint`.

#### Resource tuning for small clusters

ACS defaults are designed for production — sensor requests 2 CPU, Central requests 1.5 CPU, and scanner replicas default to 2-3. On small/workshop clusters, override in `operator-instances.yaml`:

```yaml
securedCluster:
  sensor:
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 2
        memory: 4Gi
  scannerV4:
    scannerComponent: Disabled    # delegate scanning to Central
  admissionControl:
    listenOnCreates: false         # disable webhook overhead
    listenOnUpdates: false
    listenOnEvents: false
  perNode:
    collector:
      imageFlavor: Slim            # smaller collector images
```

For Central on the hub, override in `clusters/mgt/acm-hub/operator-instances.yaml`:

```yaml
central:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
  scanner:
    analyzer:
      scaling:
        minReplicas: 1
        maxReplicas: 3
  scannerV4:
    indexer:
      scaling:
        minReplicas: 1
    matcher:
      scaling:
        minReplicas: 1
```

#### Init bundle secrets

The init bundle generation job (`secretMode: "generate"`) calls Central's API and applies the `kubectlBundle` response. This creates three secrets: `sensor-tls`, `collector-tls`, `admission-control-tls`.

**Do NOT manually create `tls-cert-*` secrets.** ACS 4.11 creates these internally from the legacy init bundle secrets. Manually creating partial `tls-cert-*` secrets triggers a CA consistency check failure that blocks operator reconciliation entirely. If you see the error `runtime-retrieved TLS secrets are not consistent (are signed by different CAs)`, delete all `tls-cert-*` secrets and restart the operator pod.

#### Init bundle timing

The init bundle job is an ArgoCD PostSync hook. It requires Central to be reachable. If Central is down (e.g. Pending due to resource pressure), the job retries for 5 minutes then fails. Fix Central first, then re-sync the ArgoCD app to re-trigger the PostSync hook.

### Platform Charts

| Chart | What it does | Config needed |
|-------|-------------|---------------|
| `tls-certificates` | API server and ingress wildcard certs (via cert-manager, manual, sealed-secret, vault, or external-secret) | `platform-config.yaml` — set `provider: cert-manager`, `certManager.issuerRef.name`, enable api + ingress certs with dnsNames |
| `openshift-apiserver` | API server config — audit logging, named certificates for custom TLS | `platform-config.yaml` — `apiServer.include: true`, add `servingCerts.namedCertificates` pointing to the cert-manager secret |
| `openshift-ingress` | Ingress controller config — replicas, placement, endpoint publishing, default cert | `platform-config.yaml` — `ingress.controller.include: true`, set `defaultCertificate` to the cert-manager ingress secret |
| `openshift-proxy` | Cluster-wide proxy and custom CA trust bundle | `platform-config.yaml` — `proxy.include: true`. Set `trustedCA.name` only if using a private CA (not needed for Let's Encrypt) |

### Post-TLS switch for ACM-managed clusters

After switching to Let's Encrypt (or any non-default CA), patch the Hive admin kubeconfig secret on the hub to remove the old `certificate-authority-data`. See [letsencrypt-dns01-setup.md](letsencrypt-dns01-setup.md#post-switch-fixing-hiveacm-connectivity).

---

## Recommended — enable on most clusters

Not strictly required to function, but expected in a well-run environment.

### Platform Charts

| Chart | What it does | Why |
|-------|-------------|-----|
| `etcd-backup` | Automated etcd backup CronJob | Disaster recovery — restoring a cluster without an etcd backup is a reinstall |
| `etcd-defrag` | Automated etcd defrag with threshold alerting | Prevents etcd performance degradation from fragmentation |
| `user-workload-monitoring` | Enables Prometheus monitoring for user workloads | Required for application teams to use ServiceMonitor/PodMonitor |
| `project-request-template` | Default namespace resources (NetworkPolicy, LimitRange, ResourceQuota) on project creation | Enforces baseline tenant isolation and resource limits |
| `machine-health-checks` | Auto-remediation of unhealthy nodes | Reduces manual intervention for node failures |
| `image-pruner` | Automatic cleanup of old images in the internal registry | Prevents storage bloat |
| `openshift-oauth` | Identity provider configuration (LDAP, OIDC, HTPasswd) | Clusters ship with kubeadmin only — set up real auth. See [OIDC setup](#openshift-oauth-with-keycloak-oidc) below |
| `openshift-console` | Console branding, links, and customization | Cluster identification — know which cluster you're looking at |
| `prometheus-rules` | Critical cluster alert rules | Fills gaps in default alerting |
| `alertmanager-config` | Alert routing and notification (Slack, PagerDuty, email) | Alerts are useless if nobody sees them |

### OpenShift OAuth with Keycloak OIDC

The hub runs Keycloak as a central IdP. Managed clusters authenticate against it using OpenID Connect. Setup has three parts: hub-side Keycloak config, managed-cluster secret, and the GitOps chart values.

#### 1. Register the cluster as a Keycloak OIDC client (hub side)

Add an `openshift` client to the Keycloak realm in the hub's `operator-instances.yaml`:

```yaml
# clusters/mgt/acm-hub/operator-instances.yaml
realm:
  clients:
    openshift:
      include: true
      clientSecret: "<generate-a-random-secret>"
      redirectUris:
        - "https://oauth-openshift.apps.<cluster-domain>/oauth2callback/<provider-name>"
      webOrigins:
        - "https://oauth-openshift.apps.<cluster-domain>"
```

The `<provider-name>` must match the `name:` in the managed cluster's `identityProviders` list (e.g. `keycloak`).

The keycloak-instance chart already includes a `groups` protocol mapper that puts Keycloak group membership into the `groups` claim on the OIDC token. This is what drives OpenShift group sync — no CronJob or group-sync operator needed.

#### 2. Create the OIDC client secret on the managed cluster

The managed cluster needs the client secret in a Secret so the OAuth server can authenticate with Keycloak. Until a sealed-secrets or external-secrets operator is available on the cluster, create it imperatively:

```bash
oc create secret generic openshift-oidc-client-secret \
  --from-literal=clientSecret='<same-secret-as-keycloak-client>' \
  -n openshift-config
```

**Known gap**: this secret is not managed by GitOps. Adding `external-secrets-operator` or `sealed-secrets` to the cluster would close this.

#### 3. Configure the openshift-oauth chart (managed cluster)

In the managed cluster's `platform-config.yaml`:

```yaml
oauth:
  include: true
  groupRBAC:
    - group: admins
      clusterRole: cluster-admin
    - group: users
      clusterRole: edit
  identityProviders:
    - name: keycloak
      type: OpenID
      mappingMethod: claim
      openID:
        clientID: openshift
        clientSecret:
          name: openshift-oidc-client-secret
        issuer: "https://sso.apps.<hub-domain>/realms/<realm>"
        claims:
          preferredUsername:
            - preferred_username
          name:
            - name
          email:
            - email
          groups:
            - groups
        extraScopes:
          - email
          - profile
```

The `groupRBAC` list creates ClusterRoleBindings that map Keycloak groups to OpenShift ClusterRoles. Groups are auto-created by the OIDC provider when users log in — the chart intentionally does **not** manage Group resources to avoid ArgoCD self-heal conflicts (ArgoCD would reset the `users` field on every sync, breaking group membership).

Add `openshift-oauth` to `conf.yaml`:

```yaml
platformCharts:
  - chart: openshift-oauth
```

#### Pitfalls

- **ArgoCD + Group resources**: Do not create Group CRs in the chart. OpenShift updates the `users` list on login. ArgoCD sees the drift, resets it, and users lose group membership. Only manage ClusterRoleBindings.
- **Orphaned identities**: If you delete a user and re-create it (or switch `mappingMethod`), the old Identity object may block login with `users.user.openshift.io "username" not found`. Fix: `oc delete identity keycloak:<username>` and `oc delete user <username>`.
- **issuer URL**: Must exactly match the Keycloak realm URL including trailing path (`/realms/<name>`). No trailing slash.
- **Hub TLS**: The managed cluster's OAuth server must trust the hub's TLS certificate. If the hub uses Let's Encrypt, this works out of the box (ISRG Root X1 is in all trust stores). If the hub uses a private CA, add it to the managed cluster's proxy trustedCA bundle.

### Operators + Instances (environment-dependent)

| Operator | Instance Chart | What it does | When to enable |
|----------|---------------|-------------|----------------|
| `compliance-operator` | `compliance-scans` | CIS/NIST compliance scanning | Regulated environments, audit requirements. See [compliance setup](#compliance-operator-setup) below |
| `gatekeeper` or `kyverno` | `gatekeeper-instance` / `kyverno-instance` | Policy admission control | When you need to enforce policy beyond what ACS covers |

### Compliance operator setup

Add `compliance-operator` to `operator-deployment.yaml` (channel: `stable`) and `compliance-scans` to `operatorInstanceCharts` in `conf.yaml`. Enable scans in `operator-instances.yaml`:

```yaml
scanSetting:
  include: true
scanSettingBinding:
  include: true
```

The chart defaults to daily STIG scans (ocp4-stig, ocp4-stig-node, rhcos4-stig profiles) at 01:00 UTC. Override `scanSetting.schedule` or `scanSettingBinding.profiles` in `operator-instances.yaml` for different profiles or timing.

**CRD quirk**: The compliance operator CRDs (ScanSetting, ScanSettingBinding) put all fields at the root level, not under `spec:`. The chart templates handle this correctly — if you're writing custom templates, don't nest fields under `spec`.

#### TailoredProfiles

To customize a compliance profile (disable checks, change thresholds), add entries to `tailoredProfiles` in `operator-instances.yaml`:

```yaml
tailoredProfiles:
  - include: true
    name: custom-stig
    title: Custom STIG Profile
    description: STIG profile with site-specific exclusions
    extends: ocp4-stig
    disableRules:
      - name: ocp4-scheduler-no-bind-address
        rationale: Not applicable in our environment
    enableRules: []
    setValues:
      - name: ocp4-var-openshift-audit-profile
        rationale: Audit profile must be WriteRequestBodies per policy
        value: WriteRequestBodies
```

Then reference the TailoredProfile in `scanSettingBinding.profiles`:

```yaml
scanSettingBinding:
  profiles:
    - name: custom-stig
      kind: TailoredProfile
      apiGroup: compliance.openshift.io/v1alpha1
```

---

## Nice to Have — enable based on workload needs

These depend on what runs on the cluster.

### Platform Charts

| Chart | What it does | When |
|-------|-------------|------|
| `storage-classes` | Custom StorageClass definitions | Non-default storage tiers needed |
| `volume-snapshot-classes` | VolumeSnapshotClass for CSI drivers | Backup/restore workflows |
| `openshift-image-registry` | Internal registry config (storage backend, routes) | Clusters that build and push images internally |
| `global-pull-secrets` | Pull secrets for external registries | Private registries, rate limit avoidance |
| `image-mirror-config` | ImageDigestMirrorSet for registry mirroring | Air-gapped or mirror-assisted environments |
| `openshift-dns` | DNS configuration (upstream resolvers, node placement) | Custom DNS requirements |
| `openshift-scheduler` | Scheduler profile (LowNodeUtilization, HighNodeUtilization) | Tuning bin-packing or spreading behavior |
| `openshift-build` | Cluster-wide build defaults | Teams using OpenShift Builds |
| `openshift-machine-config` | MachineConfig, KubeletConfig, ContainerRuntimeConfig | Node-level tuning (kernel params, cgroup settings, etc.) |
| `openshift-marketplace` | Custom CatalogSources | Custom operator catalogs or air-gapped |
| `admin-network-policy` | Cluster-scoped network policies | Cluster-wide network segmentation (OVN-Kubernetes) |
| `openshift-group-sync` | LDAP/AD group sync CronJob | LDAP-based RBAC |
| `acm-policies` | ACM governance policies | Multi-cluster policy enforcement from hub |
| `vault-server` | HashiCorp Vault with Raft storage | Centralized secrets management |

### Operators + Instances

| Operator | Instance Chart | What it does | When |
|----------|---------------|-------------|------|
| `openshift-logging` + `loki` | `logging-lokistack` | Cluster and application log aggregation | Centralized logging |
| `opentelemetry` + `tempo` | `opentelemetry-instance` + `tempo-instance` | Distributed tracing | Microservice architectures |
| `odf-operator` | `odf-storagecluster` | OpenShift Data Foundation (Ceph) | Clusters needing RWX, object storage, or distributed block |
| `openshift-local-storage` | `local-storage-volumes` | Local disk provisioning | Bare-metal, local NVMe/SSD for databases |
| `lvm` | `lvm-cluster` | LVM thin-provisioning for single-node or small clusters | SNO, compact clusters |
| `metallb` | `metallb-config` | Bare-metal load balancer | Bare-metal clusters without cloud LB |
| `nmstate` | `nmstate-config` | Declarative node network config | Complex networking (bonds, VLANs, bridges) |
| `node-feature-discovery` | `node-feature-discovery-instance` | Auto-label nodes by hardware features | GPU, SR-IOV, or hardware-specific scheduling |
| `openshift-virtualization` | `openshift-virtualization-instance` | KubeVirt for running VMs | VM workloads |
| `mtv` | `mtv-controller` | Migration Toolkit for Virtualization | VMware-to-OpenShift migrations |
| `servicemesh3` | `servicemesh3-instance` / `servicemesh-ambient` | Istio service mesh | mTLS, traffic management, observability |
| `openshift-pipelines` | — | Tekton CI/CD pipelines | CI/CD on-cluster |
| `trident` | `trident-config` | NetApp Trident CSI | NetApp storage backends |
| `external-secrets-operator` | — | ExternalSecret CRs (Vault, AWS SM, etc.) | External secret stores |
| `ansible-automation-platform` | `aap-instance` | Ansible Controller + Hub | Ansible-driven automation |
| `dev-spaces` | — | Eclipse Che cloud IDE | Developer self-service workspaces |
| `developer-hub` | — | Red Hat Developer Hub (Backstage) | Internal developer portal |
| `quay` + `quay-bridge` | `quay-registry` | Private container registry | On-prem registry |
| `keycloak` | `keycloak-instance` | Identity and SSO | Centralized IdP |
| `trusted-artifact-signer` | `trusted-artifact-signer-instance` | Sigstore-based artifact signing | Supply chain security |
| `cluster-observability` | — | COO for dashboards and observability UI | Advanced monitoring dashboards |

---

## Minimal cluster example (Critical tier only)

```yaml
# conf.yaml
platformCharts:
  - chart: tls-certificates
  - chart: openshift-apiserver
  - chart: openshift-ingress
  - chart: openshift-proxy
operatorInstanceCharts:
  - chart: cert-manager-certs
deployOperators: true
```

This gives you: TLS (Let's Encrypt or self-signed CA), API server + ingress config, ACS secured cluster (inherited from env), and GitOps. Everything else is additive.

---

## Full recommended example (aws-test today)

aws-test runs the Critical tier plus all Recommended charts including Keycloak OIDC auth:

```yaml
# conf.yaml
platformCharts:
  - chart: tls-certificates
  - chart: openshift-apiserver
  - chart: openshift-ingress
  - chart: openshift-proxy
  - chart: etcd-backup
  - chart: etcd-defrag
  - chart: user-workload-monitoring
  - chart: project-request-template
  - chart: machine-health-checks
  - chart: image-pruner
  - chart: openshift-console
  - chart: prometheus-rules
  - chart: alertmanager-config
  - chart: openshift-oauth
operatorInstanceCharts:
  - chart: cert-manager-certs
deployOperators: true
```

Key values in `platform-config.yaml`:

```yaml
# TLS via Let's Encrypt
provider: cert-manager
certManager:
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer

# etcd
etcdBackup:
  include: true
  storage:
    type: pvc
    pvc:
      storageClass: gp3-csi
etcdDefrag:
  include: true

# monitoring
userWorkloadMonitoring:
  include: true
  prometheus:
    storageClass: gp3-csi

# auth via Keycloak OIDC
oauth:
  include: true
  groupRBAC:
    - group: admins
      clusterRole: cluster-admin
    - group: users
      clusterRole: edit
  identityProviders:
    - name: keycloak
      type: OpenID
      mappingMethod: claim
      openID:
        clientID: openshift
        clientSecret:
          name: openshift-oidc-client-secret
        issuer: "https://sso.apps.<hub-domain>/realms/sso"
        claims:
          preferredUsername: [preferred_username]
          name: [name]
          email: [email]
          groups: [groups]
        extraScopes: [email, profile]
```

---

## Full cluster example (hub today)

The hub runs the management plane — ACM, ACS Central, Quay, Keycloak, Vault, AAP, and observability. See `clusters/mgt/acm-hub/conf.yaml` for the full list.

---

## How to add a chart to a new cluster

1. Add the chart name to `platformCharts` or `operatorInstanceCharts` in the cluster's `conf.yaml`
2. If the chart needs an operator, add the operator to `operator-deployment.yaml` (or inherit from env level)
3. Set values in `platform-config.yaml` (platform charts) or `operator-instances.yaml` (operator instances)
4. Push to git — ArgoCD creates an Application and syncs it

All toggles default to `include: false` in chart `values.yaml`, so adding a chart without setting any values is a no-op. Enable features explicitly.
