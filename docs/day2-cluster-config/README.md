# Day 2 Cluster Configuration Guide

What to enable on a new managed cluster after provisioning, organized by priority. Add the chart to `conf.yaml`, set values in `platform-config.yaml` / `operator-instances.yaml` / `operator-deployment.yaml`, push to git, and ArgoCD syncs it.

See [Cluster Configuration](../cluster-configuration/) for how ApplicationSets, values precedence, and `conf.yaml` work.

---

## Critical — enable on every cluster

A cluster without these is missing security controls, proper TLS, identity, or core node configuration.

### Operators

| Operator | Channel | What it does | Notes |
|----------|---------|-------------|-------|
| `openshift-gitops` | `gitops-1.21` | ArgoCD for GitOps delivery | Already set at `env/dev/` and `env/prod/` level |
| `compliance-operator` | `stable` | CIS/NIST compliance scanning | Operator on every cluster; scans configured per-need via instance chart |

### Operator Instances

| Chart | What it does | Prerequisites | Config needed |
|-------|-------------|---------------|---------------|
| `openshift-gitops-instance` | ArgoCD instance configuration | openshift-gitops operator | `operator-instances.yaml` — RBAC, plugins, HA settings |

### Platform Charts

| Chart | What it does | Config needed |
|-------|-------------|---------------|
| `tls-certificates` | API server and ingress wildcard certs (via cert-manager, manual, sealed-secret, vault, or external-secret) | `platform-config.yaml` — set `provider: cert-manager`, `certManager.issuerRef.name`, enable api + ingress certs with dnsNames |
| `openshift-apiserver` | API server config — audit logging, named certificates for custom TLS | `platform-config.yaml` — `apiServer.include: true`, add `servingCerts.namedCertificates` pointing to the cert-manager secret |
| `openshift-ingress` | Ingress controller config — replicas, placement, endpoint publishing, default cert | `platform-config.yaml` — `ingress.controller.include: true`, set `defaultCertificate` to the cert-manager ingress secret |
| `openshift-proxy` | Cluster-wide proxy and custom CA trust bundle | `platform-config.yaml` — `proxy.include: true`. Set `trustedCA.name` only if using a private CA (not needed for Let's Encrypt) |
| `openshift-oauth` | Identity provider configuration (LDAP, OIDC, HTPasswd) | `platform-config.yaml` — clusters ship with kubeadmin only. See [OAuth/Keycloak setup](oauth-keycloak.md) |
| `openshift-image-registry` | Internal registry config (storage backend, routes) | `platform-config.yaml` — `imageRegistry.include: true`, set storage type |
| `global-pull-secrets` | Pull secrets for external registries | `platform-config.yaml` — `pullSecrets.include: true` |
| `openshift-machine-config` | MachineConfig, KubeletConfig, ContainerRuntimeConfig | `platform-config.yaml` — node-level tuning (kubelet, chrony, kernel params) |
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
| `acm-policies` | ACM governance policies (hub-driven) | Multi-cluster policy enforcement |

### Operators + Instances

| Operator | Instance Chart | What it does | Notes |
|----------|---------------|-------------|-------|
| `advanced-cluster-security` | `acs-secured-cluster` | Container security (StackRox) | Already set at env level; ACS Central runs on hub only. See [ACS setup](acs-setup.md) |
| `compliance-operator` | `compliance-scans` | CIS/NIST compliance scanning | Operator is Critical (every cluster); scans configured per-need. See [compliance setup](compliance.md) |
| `advanced-cluster-management` | `acm-multiclusterhub` | Multi-cluster management | Hub only |
| — | `acm-observability` | ACM multi-cluster observability | Hub only |
| — | `acs-central` | ACS Central services | Hub only |
| `openshift-logging` + `loki` | `logging-lokistack` | Cluster and application log aggregation | Centralized logging |
| `odf-operator` | `odf-storagecluster` | OpenShift Data Foundation (Ceph) | RWX, object storage, or distributed block |
| `openshift-local-storage` | `local-storage-volumes` | Local disk provisioning | Bare-metal, local NVMe/SSD |

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

### Operators + Instances

| Operator | Instance Chart | What it does | When |
|----------|---------------|-------------|------|
| `cert-manager` | `cert-manager-certs` | Certificate lifecycle management + ClusterIssuers | When TLS automation uses cert-manager (not all clusters need the operator separately) |
| `gatekeeper` or `kyverno` | `gatekeeper-instance` / `kyverno-instance` | Policy admission control | Policy enforcement beyond what ACS covers |
| `opentelemetry` + `tempo` | `opentelemetry-instance` + `tempo-instance` | Distributed tracing | Microservice architectures |
| `lvm` | `lvm-cluster` | LVM thin-provisioning for single-node or small clusters | SNO, compact clusters |
| `metallb` | `metallb-config` | Bare-metal load balancer | Bare-metal clusters without cloud LB |
| `nmstate` | `nmstate-config` | Declarative node network config | Complex networking (bonds, VLANs, bridges) |
| `node-feature-discovery` | `node-feature-discovery-instance` | Auto-label nodes by hardware features | GPU, SR-IOV, or hardware-specific scheduling |
| `openshift-virtualization` | `openshift-virtualization-instance` | KubeVirt for running VMs | VM workloads |
| `mtv` | `mtv-controller` | Migration Toolkit for Virtualization | VMware-to-OpenShift migrations |
| `servicemesh3` | `servicemesh3-instance` / `servicemesh-ambient` | Istio service mesh | mTLS, traffic management, observability |
| `openshift-pipelines` | — | Tekton CI/CD pipelines | CI/CD on-cluster |
| `trident` | `trident-config` | NetApp Trident CSI | NetApp storage backends |
| `external-secrets-operator` | `external-secrets` | ExternalSecret CRs (Vault, AWS SM, etc.) | External secret stores |
| `ansible-automation-platform` | `aap-instance` | Ansible Controller + Hub | Ansible-driven automation |
| `dev-spaces` | — | Eclipse Che cloud IDE | Developer self-service workspaces |
| `developer-hub` | — | Red Hat Developer Hub (Backstage) | Internal developer portal |
| `quay` + `quay-bridge` | `quay-registry` | Private container registry | On-prem registry. See [Quay registry setup](quay-registry.md) |
| `keycloak` | `keycloak-instance` | Identity and SSO | Centralized IdP |
| `trusted-artifact-signer` | `trusted-artifact-signer-instance` | Sigstore-based artifact signing | Supply chain security |
| `group-sync-operator` | `group-sync` | LDAP/AD group sync (community operator) | LDAP/AD group sync |
| `cluster-observability` | — | COO for dashboards and observability UI | Advanced monitoring dashboards |

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
operatorInstanceCharts:
  - chart: openshift-gitops-instance
deployOperators: true
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
  - chart: acm-policies
operatorInstanceCharts:
  - chart: openshift-gitops-instance
  - chart: acs-secured-cluster
  - chart: compliance-scans
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

### Hub cluster

The hub runs the management plane — ACM, ACS Central, Quay, Keycloak, Vault, AAP, and observability. See `clusters/mgt/acm-hub/conf.yaml` for the full list.
