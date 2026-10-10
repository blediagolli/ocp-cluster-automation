# Day 2 Cluster Configuration Guide

What to enable on a new managed cluster after provisioning, organized by priority. Add the chart to `conf.yaml`, set values in `platform-config.yaml` or `operators.yaml`, push to git, and ArgoCD syncs it.

See [Cluster Configuration](../cluster-configuration/) for how ApplicationSets, values precedence, and `conf.yaml` work.

---

## Critical — enable on every cluster

A cluster without these is missing security controls, proper TLS, identity, or core node configuration.

### Operators

Each chart installs its operator and renders its CRs. Listing it installs the operator only — the CRs have their own `include: false` defaults.

| Chart | Channel | What it does | Notes |
|-------|---------|-------------|-------|
| `openshift-gitops` | `gitops-1.21` | ArgoCD for GitOps delivery, plus the ArgoCD CR, AppProject and console plugin | Already set at `env/dev/` and `env/prod/` level. The ArgoCD CR is off by default — turning it on has the Application manage the ArgoCD running it |
| `compliance` | `stable` | CIS/NIST compliance scanning, plus ScanSetting and ScanSettingBinding | Operator on every cluster; scans enabled per-need |

### Platform Charts

| Chart | What it does | Config needed |
|-------|-------------|---------------|
| `tls-certificates` | API server and ingress wildcard certs (via cert-manager, sealed-secret, or an existing cert from a [secrets source](../cluster-configuration/secrets.md)) | `platform-config.yaml` — set `provider: cert-manager`, `certManager.issuerRef.name`, enable api + ingress certs with dnsNames |
| `openshift-apiserver` | API server config — audit logging, named certificates for custom TLS | `platform-config.yaml` — `apiServer.include: true`, add `servingCerts.namedCertificates` pointing to the cert-manager secret |
| `openshift-ingress` | Ingress controller config — replicas, placement, endpoint publishing, default cert | `platform-config.yaml` — `ingress.controller.include: true`, set `defaultCertificate` to the cert-manager ingress secret |
| `openshift-proxy` | Cluster-wide proxy and custom CA trust bundle | `platform-config.yaml` — `proxy.include: true`. Set `trustedCA.name` only if using a private CA (not needed for Let's Encrypt) |
| `openshift-oauth` | Identity provider configuration (LDAP, OIDC, HTPasswd) | `platform-config.yaml` — clusters ship with kubeadmin only. See [OAuth/Keycloak setup](oauth-keycloak.md) |
| `openshift-image-registry` | Internal registry config (storage backend, routes) | `platform-config.yaml` — `imageRegistry.include: true`, set storage type |
| `global-pull-secrets` | Pull secrets for external registries | `platform-config.yaml` — `pullSecrets.include: true` |
| `openshift-machine-config` | MachineConfig, KubeletConfig, ContainerRuntimeConfig | `platform-config.yaml` — node-level tuning (kubelet, chrony, kernel params) and hardware prerequisites (Pure FlashArray multipath/udev/iSCSI) |
| `acm-managed-cluster` | ManagedCluster resource configuration | ACM on the hub | `platform-config.yaml` — `managedCluster.include: true`, set clusterSet and labels |

### Post-TLS switch for ACM-managed clusters

After switching to Let's Encrypt (or any non-default CA), patch the Hive admin kubeconfig secret on the hub to remove the old `certificate-authority-data`. See [letsencrypt-dns01-setup.md](letsencrypt-dns01-setup.md#post-switch-fixing-hiveacm-connectivity).

---

## Recommended — enable on most clusters

Not strictly required to function, but expected in a well-run environment.

### Platform Charts

| Chart | What it does | Why |
|-------|-------------|-----|
| `etcd-backup` | Automated etcd backup CronJob | Disaster recovery — restoring without a backup is a reinstall |
| `etcd-defrag` | Automated etcd defrag with threshold alerting | Prevents etcd performance degradation from fragmentation |
| `user-workload-monitoring` | Enables Prometheus monitoring for user workloads | Required for application teams to use ServiceMonitor/PodMonitor |
| `project-request-template` | Default namespace resources (NetworkPolicy, LimitRange, ResourceQuota) on project creation | Enforces baseline tenant isolation and resource limits |
| `machine-health-checks` | Auto-remediation of unhealthy nodes | Reduces manual intervention for node failures |
| `image-pruner` | Automatic cleanup of old images in the internal registry | Prevents storage bloat |
| `openshift-console` | Console branding, links, and customization | Cluster identification — know which cluster you're looking at |
| `prometheus-rules` | Critical cluster alert rules | Fills gaps in default alerting |
| `alertmanager-config` | Alert routing and notification (Slack, PagerDuty, email) | Alerts are useless if nobody sees them |
| `rbac` | Cluster RBAC — ClusterRoles, ClusterRoleBindings | Standard role definitions across clusters |
| `openshift-build` | Cluster-wide build defaults | Standard build config for teams using OpenShift Builds |
| `openshift-group-sync` | LDAP/AD group sync CronJob | RBAC driven by directory groups |

ACM governance policies are deliberately **not** a platform chart. They are
authored once on the hub rather than per cluster, so they live in `policies/`
at the repo root and are delivered by their own ApplicationSet. Charts
configure; policies attest. See [governance](../governance/acm-policies.md).

### Operators

| Chart | CRs it carries | What it does | Notes |
|-------|---------------|-------------|-------|
| `advanced-cluster-security` | `central`, `securedCluster` | Container security (StackRox) | Already set at env level; Central on the hub, SecuredCluster everywhere. See [ACS setup](acs-setup.md) |
| `compliance` | `scanSetting`, `scanSettingBinding`, `tailoredProfiles` | CIS/NIST compliance scanning | Operator is Critical (every cluster); scans enabled per-need. See [compliance setup](compliance.md) |
| `advanced-cluster-management` | `multiClusterHub`, `multiClusterObservability` | Multi-cluster management and observability | Hub only. Observability needs ODF object storage |
| `logging` | `lokiStack`, `clusterLogForwarder` | Cluster and application log aggregation | `extraOperators.loki` installs loki-operator alongside |
| `odf` | `storageCluster` | OpenShift Data Foundation (Ceph) | RWX, object storage, or distributed block |
| `openshift-local-storage` | `localVolumes` | Local disk provisioning | Bare-metal, local NVMe/SSD |

---

## Nice to Have — enable based on workload needs

These depend on what runs on the cluster.

### Platform Charts

| Chart | What it does | When |
|-------|-------------|------|
| `storage-classes` | Custom StorageClass definitions | Non-default storage tiers needed |
| `volume-snapshot-classes` | VolumeSnapshotClass for CSI drivers | Backup/restore workflows |
| `openshift-image` | Cluster-wide image configuration (registries, policies) | Registry allow/block lists |
| `image-mirror-config` | ImageDigestMirrorSet for registry mirroring | Air-gapped or mirror-assisted environments |
| `openshift-dns` | DNS configuration (upstream resolvers, node placement) | Custom DNS requirements |
| `openshift-scheduler` | Scheduler profile (LowNodeUtilization, HighNodeUtilization) | Tuning bin-packing or spreading behavior |
| `openshift-marketplace` | Custom CatalogSources | Custom operator catalogs or air-gapped |
| `admin-network-policy` | Cluster-scoped network policies | Cluster-wide network segmentation (OVN-Kubernetes) |
| `vault-server` | HashiCorp Vault with Raft storage | Centralized secrets management |

### Operators

| Chart | What it does | When |
|-------|-------------|------|
| `cert-manager` | Certificate lifecycle management + ClusterIssuers | When TLS automation uses cert-manager |
| `gatekeeper` or `kyverno` | Policy admission control | Policy enforcement beyond what ACS covers |
| `opentelemetry` + `tempo` | Distributed tracing | Microservice architectures |
| `lvm` | LVM thin-provisioning for single-node or small clusters | SNO, compact clusters |
| `metallb` | Bare-metal load balancer | Bare-metal clusters without cloud LB |
| `nmstate` | Declarative node network config | Complex networking (bonds, VLANs, bridges) |
| `node-feature-discovery` | Auto-label nodes by hardware features | GPU, SR-IOV, or hardware-specific scheduling |
| `node-maintenance` | Cordon and drain via NodeMaintenance CRs | Bare-metal node servicing |
| `openshift-virtualization` | KubeVirt for running VMs | VM workloads |
| `mtv` | Migration Toolkit for Virtualization | VMware-to-OpenShift migrations |
| `servicemesh3` | Istio service mesh, sidecar or ambient | mTLS, traffic management, observability |
| `openshift-pipelines` | Tekton CI/CD pipelines | CI/CD on-cluster |
| `trident` | NetApp Trident CSI | NetApp storage backends |
| `portworx` | Portworx operator + a PX-CSI StorageCluster | Pure FlashArray backends. PX-CSI, not Portworx Enterprise. Needs `pureStorage` in `openshift-machine-config` on the nodes first |
| `external-secrets` | External Secrets Operator + ExternalSecret CRs | External secret stores (Vault, AWS SM) |
| `ansible-automation-platform` | Ansible Controller + Hub | Ansible-driven automation |
| `dev-spaces` | Eclipse Che cloud IDE | Developer self-service workspaces |
| `developer-hub` | Red Hat Developer Hub (Backstage) | Internal developer portal |
| `quay` + `quay-bridge` | Private container registry, and its cluster integration | On-prem registry. See [Quay registry setup](quay-registry.md) |
| `keycloak` | Identity and SSO | Centralized IdP |
| `trusted-artifact-signer` | Sigstore-based artifact signing | Supply chain security |
| `group-sync` | LDAP/AD group sync (community operator) | LDAP/AD group sync |
| `cluster-observability` | COO UIPlugins, MonitoringStacks, ThanosQueriers | Advanced monitoring dashboards |
| `oadp` | OADP/Velero backup and restore | Cluster and application backup |
| `cost-management-metrics` + `cost-management-service` | Cost reporting | Chargeback and showback |
| `amq-streams`, `cloudnative-pg`, `gitlab`, `gitlab-runner`, `jfrog` | Kafka, PostgreSQL, GitLab, CI runners, Artifactory | Application platform building blocks |

---

## Cluster examples

### Minimal (Critical tier only)

```yaml
# conf.yaml
platformCharts:
  - chart: tls-certificates
  - chart: openshift-apiserver
  - chart: openshift-ingress
  - chart: openshift-proxy
  - chart: openshift-oauth
  - chart: openshift-image-registry
  - chart: global-pull-secrets
  - chart: openshift-machine-config
  - chart: acm-managed-cluster
operatorCharts:
  - chart: openshift-gitops
installOperators: true
```

This gives you: TLS (Let's Encrypt or self-signed CA), API server + ingress config, identity, registry, node config, and GitOps. Everything else is additive.

### Full recommended (example-cluster today)

example-cluster runs the Critical tier plus all Recommended charts including Keycloak OIDC auth:

```yaml
# conf.yaml
platformCharts:
  # Critical
  - chart: tls-certificates
  - chart: openshift-apiserver
  - chart: openshift-ingress
  - chart: openshift-proxy
  - chart: openshift-oauth
  - chart: openshift-image-registry
  - chart: global-pull-secrets
  - chart: openshift-machine-config
  - chart: acm-managed-cluster
  # Recommended
  - chart: etcd-backup
  - chart: etcd-defrag
  - chart: user-workload-monitoring
  - chart: project-request-template
  - chart: machine-health-checks
  - chart: image-pruner
  - chart: openshift-console
  - chart: prometheus-rules
  - chart: alertmanager-config
  - chart: rbac
  - chart: openshift-build
  - chart: openshift-group-sync
operatorCharts:
  - chart: openshift-gitops
  - chart: advanced-cluster-security
  - chart: compliance
installOperators: true
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

### Hub cluster

The hub runs the management plane — ACM, ACS Central, Quay, Keycloak, Vault, AAP, and observability. See `clusters/mgt/acm-hub/conf.yaml` for the full list.
