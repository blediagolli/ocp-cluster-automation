# Part 1: Provisioning OpenShift Clusters with GitOps and ACM

This guide covers how clusters are provisioned using Red Hat Advanced Cluster Management (ACM), Hive, and ArgoCD — all driven by git commits.

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

## Cluster definition files

### conf.yaml

The cluster identity file. ApplicationSets discover clusters by scanning for `clusters/**/conf.yaml`.

```yaml
cluster:
  name: aws-test
  environment: dev
  address: "https://cluster-proxy-addon-user.multicluster-engine.svc.cluster.local:9092/aws-test"
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

Provisioning-specific values consumed by `charts/cluster-provisioning/openshift-provisioning/`.

**AWS example:**

```yaml
provision:
  include: true

cluster:
  name: aws-test
  baseDomain: example.com
  platform: aws
  environment: dev
  clusterSet: default
  imageSetRef: img4.22.13-x86-64-appsub
  networkType: OVNKubernetes
  sshPublicKey: "ssh-ed25519 AAAA..."

masters:
  count: 3

workers:
  count: 3

aws:
  region: us-east-2
  masters:
    instanceType: m5.xlarge
    rootVolume:
      size: 120
      type: gp3
  workers:
    instanceType: m5.xlarge
    rootVolume:
      size: 120
      type: gp3
```

For baremetal provisioning with the agent-based installer, see [Baremetal.md](Baremetal.md).

## Provisioning chart

The Helm chart at `charts/cluster-provisioning/openshift-provisioning/` generates all the ACM/Hive resources:

| Resource | Purpose |
|---|---|
| Namespace | Cluster namespace on the hub |
| ClusterDeployment | Defines the cluster for Hive |
| AgentClusterInstall | Networking, platform, and install config |
| InfraEnv | Discovery ISO generation |
| NMStateConfig | Static network configuration per host |
| BareMetalHost | Physical/virtual host representation |
| ManagedCluster | ACM cluster registration |
| KlusterletAddonConfig | ACM addon configuration |
| Secrets | Pull secret, SSH key, BMC credentials, cloud credentials |

The chart also includes templates for vSphere control-plane automation and custom install manifests.

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

Once imported, the cluster is registered in OpenShift GitOps and the configuration ApplicationSets begin deploying platform charts, operators, and team onboarding. See [Part 2](Part-2.md) for how cluster configuration works.

## Adding a new cluster

1. Copy an existing cluster directory:
   ```bash
   cp -r clusters/dev/aws-test clusters/dev/my-cluster
   ```

2. Edit `conf.yaml` — set cluster name, environment, base domain, chart lists, and deploy toggles

3. Edit `provision.yaml` — set platform-specific provisioning values (AWS, vSphere, or baremetal)

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
- For AWS: credentials with EC2 and Route53 permissions
- For baremetal: BMC access (Redfish) to target hosts — see [Baremetal.md](Baremetal.md)
- For vSphere: vCenter credentials and network access
- A git repository accessible from the hub cluster
