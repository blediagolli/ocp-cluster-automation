# Part 2: Configuring Clusters with ApplicationSets and Helm

This guide covers how clusters are configured after provisioning — operators, platform settings, and team onboarding — all driven by Helm charts and ArgoCD ApplicationSets.

## Overview

Eight ApplicationSets on the hub cluster drive the entire cluster lifecycle. Each watches `clusters/**/conf.yaml` for cluster definitions and uses conditional generators to decide what to deploy.

| ApplicationSet | Deploys | Gate |
|---|---|---|
| `cluster-platform-config` | Platform Helm charts (TLS, OAuth, etcd, ingress, monitoring, ...) | `platformCharts` list |
| `cluster-operator-instances` | Operator CR charts (ACS, cert-manager, Keycloak, Quay, ...) | `operatorInstanceCharts` list |
| `cluster-operators-appset` | Operator Subscriptions via OLM | `deployOperators: true` |
| `cluster-config-overlays` | Cluster-specific raw manifests | `deployOverlay: true` |
| `cluster-import` | ManagedCluster + KlusterletAddonConfig | `deployImport: true` |
| `cluster-provisioning` | ACM/Hive provisioning resources | `deployProvision: true` |
| `cluster-onboarding-gitops` | ArgoCD AppProjects per team | `teams` list |
| `cluster-onboarding-namespaces` | Team namespaces with quotas and policies | `teams` list |

## How ApplicationSets generate Applications

### Matrix generator with elementsYaml

The platform-config and operator-instances ApplicationSets use a matrix generator that crosses the git file generator (discovers clusters) with a dynamic list from the cluster's `conf.yaml`.

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
            elementsYaml: "{{ .platformCharts | toJson }}"
```

For a cluster with `platformCharts: [{chart: tls-certificates}, {chart: openshift-ingress}]`, this generates two ArgoCD Applications:
- `platform-dev-my-cluster-tls-certificates`
- `platform-dev-my-cluster-openshift-ingress`

### Boolean gates with conditional lists

The provisioning, import, overlay, and operators ApplicationSets use a conditional pattern to gate on a boolean:

```yaml
elementsYaml: "{{ if .deployProvision }}[{}]{{ else }}[]{{ end }}"
```

If `deployProvision: false` (or absent), the list is empty and no Application is generated.

## Chart categories

### Platform config (`charts/platform-config/`)

Day-2 platform configuration charts. Each chart manages a specific OpenShift subsystem.

Examples: `tls-certificates`, `openshift-apiserver`, `openshift-ingress`, `openshift-oauth`, `etcd-backup`, `etcd-defrag`, `user-workload-monitoring`, `project-request-template`, `prometheus-rules`, `alertmanager-config`, `openshift-console`, `machine-health-checks`, `image-pruner`, `rbac`, `storage-classes`, `admin-network-policy`.

### Operator instances (`charts/operator-instances/`)

Charts that deploy Custom Resources for operators — the operator's actual workload configuration (not the operator itself).

Examples: `cert-manager-certs`, `acs-secured-cluster`, `compliance-scans`, `keycloak-instance`, `quay-registry`, `odf-storagecluster`, `logging-lokistack`.

### Operator deployment (`charts/operator-deployment/`)

A single chart that manages all operator Subscriptions via OLM. Controlled by `deployOperators: true` and values in `operator-deployment.yaml`.

### Onboarding (`charts/onboarding/`)

Team onboarding charts. The `teams` list in `conf.yaml` drives these — each team gets an ArgoCD AppProject and a set of namespaces with ResourceQuotas, LimitRanges, and NetworkPolicies.

### Cluster provisioning (`charts/cluster-provisioning/`)

Covered in [Part 1](Part-1.md).

## Values precedence

Every ApplicationSet merges Helm values from multiple files, with more-specific files overriding less-specific ones:

```
chart defaults (values.yaml)
  → env/<env>/<values-file>.yaml       (environment-level)
  → clusters/<env>/<name>/<values-file>.yaml  (cluster-level)
```

The values file name depends on the ApplicationSet:

| ApplicationSet | Values files merged |
|---|---|
| `cluster-platform-config` | `conf.yaml` + `platform-config.yaml` |
| `cluster-operator-instances` | `conf.yaml` + `operator-instances.yaml` |
| `cluster-operators-appset` | `conf.yaml` + `operator-deployment.yaml` |
| `cluster-provisioning` | `provision.yaml` |

All ApplicationSets use `ignoreMissingValueFiles: true`, so absent files are silently skipped.

## The include pattern

Every feature in every chart defaults to `include: false` in the chart's `values.yaml`. Nothing deploys unless explicitly enabled.

```yaml
# charts/platform-config/openshift-oauth/values.yaml
oauth:
  include: false

# clusters/dev/my-cluster/platform-config.yaml
oauth:
  include: true
  identityProviders:
    - name: keycloak
      type: OpenID
      ...
```

This makes charts safe to add to `platformCharts` — adding the chart name doesn't deploy anything until you set `include: true` for the relevant features.

## conf.yaml structure

The `conf.yaml` file is the cluster identity. It controls which ApplicationSets generate Applications for this cluster.

```yaml
cluster:
  name: aws-test
  environment: dev
  address: "https://cluster-proxy-addon-user.multicluster-engine.svc.cluster.local:9092/aws-test"
  baseDomain: example.com

# Charts to deploy
platformCharts:
  - chart: tls-certificates
  - chart: openshift-apiserver
  - chart: openshift-ingress
  - chart: openshift-proxy
  - chart: etcd-backup
  - chart: openshift-oauth

operatorInstanceCharts:
  - chart: cert-manager-certs
  - chart: acs-secured-cluster

# Boolean gates
deployOperators: true
deployOverlay: false
deployImport: true
deployProvision: true

# Team onboarding
teams:
  - team: team-alpha
  - team: team-beta
```

### Adding a chart to a cluster

1. Add the chart name to `platformCharts` or `operatorInstanceCharts` in `conf.yaml`
2. Set values in the corresponding file (`platform-config.yaml` or `operator-instances.yaml`)
3. Push to git — ArgoCD creates the Application and syncs it

### Removing a chart from a cluster

Remove the chart entry from `platformCharts` or `operatorInstanceCharts`. The Application is deleted, but `preserveResourcesOnDeletion` keeps the deployed resources intact on the target cluster.

## Environment-level defaults

The `env/<env>/` directory holds shared defaults for all clusters in an environment. Cluster-level files override these.

```
env/
  dev/
    conf.yaml                  # shared cluster identity defaults
    platform-config.yaml       # shared platform chart values
    operator-instances.yaml    # shared operator instance values
    operator-deployment.yaml   # shared operator subscription values
  mgt/
    ...
  prod/
    ...
```

This avoids repeating the same values across every cluster in an environment.

## preserveResourcesOnDeletion

All 8 ApplicationSets set `preserveResourcesOnDeletion: true` at both the ApplicationSet and Application level. This means:

- Deleting a chart from `conf.yaml` removes the ArgoCD Application but **not** the resources on the target cluster
- Deleting the ApplicationSet itself removes Applications but preserves deployed resources
- This prevents accidental resource deletion from git changes

## Further reading

- [Day 2 cluster configuration guide](day2-cluster-config.md) — what to enable on each cluster, organized by priority tier
- [Part 1: Provisioning clusters](Part-1.md) — how clusters are provisioned with ACM/Hive
- [Baremetal provisioning](Baremetal.md) — agent-based installer for baremetal and platform-none
