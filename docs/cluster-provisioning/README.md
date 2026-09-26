# Cluster Provisioning

This guide covers how OpenShift clusters are provisioned using Red Hat Advanced Cluster Management (ACM), Hive, and ArgoCD — all driven by git commits.

## Overview

To provision a new cluster:

1. Create a directory under `clusters/<env>/<name>/`
2. Define the cluster identity in `conf.yaml` (with `deployProvision: true`)
3. Define provisioning parameters in `provision.yaml`
4. Push to git

The `cluster-provisioning` ApplicationSet detects the new cluster directory and creates an ArgoCD Application that syncs the provisioning Helm chart. ACM/Hive takes over from there — creating infrastructure, installing OpenShift, and importing the cluster.

```
Hub cluster (ACM + OpenShift GitOps)
  │
  ├── cluster-provisioning ApplicationSet
  │     watches: clusters/**/conf.yaml where deployProvision: true
  │     deploys: charts/cluster-provisioning/openshift-provisioning/
  │
  ├── cluster-import ApplicationSet
  │     watches: clusters/**/conf.yaml where deployImport: true
  │     handles: ManagedCluster, KlusterletAddonConfig
  │
  └── ACM / Hive controllers
        process: ClusterDeployment, AgentClusterInstall, InfraEnv, BareMetalHost
```

After provisioning completes, the remaining ApplicationSets (`cluster-platform-config`, `cluster-operator-instances`, `cluster-operators-appset`, `cluster-onboarding-*`) begin configuring the cluster automatically.

## Provisioning models

The chart uses two provisioning models determined by `cluster.platform`:

| Model | Platforms | How it works |
|---|---|---|
| **IPI** (Installer-Provisioned Infrastructure) | `aws`, `vsphere` | Hive drives the OpenShift installer. The installer creates infrastructure (VMs, networking) and installs the cluster. |
| **Agent-based** | `baremetal`, `none` | The Assisted Installer discovers hosts via a discovery ISO. Hosts boot the ISO, register with the hub, and the install begins once all hosts are validated. |

The `_helpers.tpl` defines two helpers — `isIPI` and `isAgent` — that gate which templates render:

- **IPI only**: MachinePool, install-config Secret, SSH private key Secret, custom manifests ConfigMap
- **Agent only**: AgentClusterInstall, InfraEnv, NMStateConfig, BareMetalHost, BMC credential Secrets
- **Both**: Namespace, ClusterDeployment, ManagedCluster, KlusterletAddonConfig, pull secret Secret

## Platform guides

- [AWS (IPI)](aws.md) — standard cloud provisioning on AWS
- [vSphere (IPI)](vsphere.md) — standard provisioning on VMware vSphere
- [Baremetal (agent-based)](baremetal.md) — physical servers with BMC/Redfish
- [Platform None (agent-based)](platform-none.md) — user-managed infrastructure, sushy-EC2 emulator
- [vSphere Control Plane (hybrid)](vsphere-control-plane.md) — vSphere VMs for control plane + baremetal workers

## Cluster definition files

### conf.yaml

The cluster identity file. ApplicationSets discover clusters by scanning for `clusters/**/conf.yaml`.

```yaml
cluster:
  name: example-cluster
  environment: dev
  address: "https://cluster-proxy-addon-user.multicluster-engine.svc.cluster.local:9092/example-cluster"
  baseDomain: example.com

platformCharts:
  - chart: tls-certificates
  - chart: openshift-apiserver
  - chart: openshift-ingress

operatorInstanceCharts:
  - chart: cert-manager-certs

deployOperators: true
deployImport: true
deployProvision: true
```

The `cluster.address` field tells ArgoCD how to reach the cluster. For ACM-managed clusters, this typically uses the cluster-proxy addon URL.

### provision.yaml

Provisioning-specific values consumed by `charts/cluster-provisioning/openshift-provisioning/`. The structure varies by platform — see the platform guides above.

Common fields across all platforms:

```yaml
provision:
  include: true

cluster:
  name: my-cluster
  baseDomain: example.com
  platform: aws          # aws | vsphere | baremetal | none
  environment: dev
  clusterSet: default
  imageSetRef: img4.22.13-x86-64-appsub
  networkType: OVNKubernetes
  sshPublicKey: "ssh-ed25519 AAAA..."
  fips: false

fleet:
  operatorClusterType: dev
  operatorProfile: ocp-4.22

masters:
  count: 3

workers:
  count: 3
```

## Cross-platform features

### Proxy configuration

All platforms support cluster-wide proxy settings. For IPI platforms, the proxy is added to the install-config. For agent-based platforms, it's set on the AgentClusterInstall and InfraEnv.

```yaml
proxy:
  enabled: true
  httpProxy: "http://proxy.internal.example.com:3128"
  httpsProxy: "http://proxy.internal.example.com:3128"
  noProxy: ".internal.example.com,.cluster.local,10.128.0.0/14,172.30.0.0/16"
```

### NTP sources (agent-based only)

Agent-based platforms can inject NTP sources into the discovery ISO via InfraEnv:

```yaml
ntp:
  enabled: true
  sources:
    - ntp1.internal.example.com
    - ntp2.internal.example.com
```

### Ignition config override (agent-based only)

Agent-based platforms can inject custom ignition into the discovery ISO (e.g., internal CA certificates):

```yaml
ignitionConfigOverride:
  enabled: true
  config: '{"ignition":{"version":"3.1.0"},"storage":{"files":[{"path":"/etc/pki/ca-trust/source/anchors/internal-ca.pem","mode":420,"contents":{"source":"data:text/plain;base64,LS0tLS1C..."}}]}}'
```

### Custom manifests (IPI only)

Day-0 customizations (NTP, kernel args, custom MachineConfigs) injected into the install via a ConfigMap referenced by the ClusterDeployment's `manifestsConfigMapRef`:

```yaml
customManifests:
  enabled: true
  data:
    99-chrony-masters.yaml: |
      apiVersion: machineconfiguration.openshift.io/v1
      kind: MachineConfig
      metadata:
        labels:
          machineconfiguration.openshift.io/role: master
        name: 99-chrony-masters
      spec:
        config:
          ignition:
            version: 3.2.0
          storage:
            files:
              - path: /etc/chrony.conf
                mode: 0644
                contents:
                  source: data:text/plain;charset=utf-8;base64,<base64-encoded-config>
```

### Additional trust bundle

For clusters behind a TLS-intercepting proxy or using an internal CA:

```yaml
cluster:
  additionalTrustBundle: |
    -----BEGIN CERTIFICATE-----
    MIIDkTCCAnmgAwIBAgI...
    -----END CERTIFICATE-----
```

### Disconnected registry

For air-gapped environments with a local mirror registry:

```yaml
imageContentSources:
  enabled: true
  mirror: registry.disconnected.example.com/openshift4
  registry: registry.disconnected.example.com
  username: registry-user
  password: registry-password
  email: platform@example.com
```

### FIPS mode

Enable FIPS 140-2 compliant cryptography:

```yaml
cluster:
  fips: true
```

## The cluster-provisioning ApplicationSet

The ApplicationSet uses a matrix generator: git files (`clusters/**/conf.yaml`) crossed with a conditional list that evaluates `deployProvision`. If `deployProvision: true`, an ArgoCD Application is created.

```yaml
generators:
  - matrix:
      generators:
        - git:
            repoURL: git@github.com:YOUR_ORG/gitops-for-organizations.git
            revision: main
            files:
              - path: "clusters/**/conf.yaml"
        - list:
            elementsYaml: "{{ if .deployProvision }}[{}]{{ else }}[]{{ end }}"
```

The Application points to `charts/cluster-provisioning/openshift-provisioning` and merges values in order:

```
charts/cluster-provisioning/openshift-provisioning/values.yaml  (chart defaults)
  → env/<env>/provision.yaml                                     (environment defaults)
  → clusters/<env>/<name>/provision.yaml                         (cluster-specific)
```

Missing value files are silently skipped (`ignoreMissingValueFiles: true`).

### preserveResourcesOnDeletion

All ApplicationSets in this repo set `preserveResourcesOnDeletion: true`. If the ApplicationSet itself is deleted, the generated Applications are removed but the underlying resources (ManagedCluster, ClusterDeployment, etc.) are preserved. This prevents accidentally destroying clusters by deleting an ApplicationSet.

## Cluster import

After provisioning completes, ACM imports the cluster. The `cluster-import` ApplicationSet (gated by `deployImport: true`) manages the ManagedCluster and KlusterletAddonConfig resources on the hub.

Once imported, the cluster is registered in OpenShift GitOps and the configuration ApplicationSets begin deploying platform charts, operators, and team onboarding. See [Cluster Configuration](../cluster-configuration/) for how that works.

## Adding a new cluster

1. Copy an existing cluster directory:
   ```bash
   cp -r clusters/dev/example-cluster clusters/dev/my-cluster
   ```

2. Edit `conf.yaml` — set cluster name, environment, base domain, chart lists, and deploy toggles

3. Edit `provision.yaml` — set platform-specific provisioning values

4. Push to git:
   ```bash
   git add clusters/dev/my-cluster/
   git commit -m "feat: provision my-cluster in dev"
   git push
   ```

5. Monitor in ArgoCD — the provisioning Application appears automatically

## Prerequisites

- OpenShift hub cluster with:
  - Red Hat ACM (MultiClusterHub deployed)
  - OpenShift GitOps (ArgoCD)
  - The 8 ApplicationSets bootstrapped (see `clusters/mgt/acm-hub/applicationsets/`)
- Platform-specific requirements listed in each platform guide
- A git repository accessible from the hub cluster
