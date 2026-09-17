# Cluster Configuration

How clusters are configured after provisioning — operators, platform settings, and team onboarding — all driven by Helm charts and ArgoCD ApplicationSets.

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

The platform-config and operator-instances ApplicationSets use a [matrix generator](applicationsets.md#matrix-generator-with-elementsyaml) to cross-match clusters with their chart lists. The remaining ApplicationSets use [boolean gates](applicationsets.md#boolean-gates-with-conditional-lists) to conditionally generate Applications.

## Chart categories

| Category | Directory | Description | Driven by |
|---|---|---|---|
| Platform config | `charts/platform-config/` | Day-2 platform charts (TLS, OAuth, etcd, ingress, monitoring, RBAC, ...) | `platformCharts` list |
| Operator instances | `charts/operator-instances/` | Operator CR charts — the operator's workload configuration | `operatorInstanceCharts` list |
| Operator deployment | `charts/operator-deployment/` | Single chart managing all operator Subscriptions via OLM | `deployOperators: true` |
| Onboarding | `charts/onboarding/` | Team ArgoCD projects and namespaces with quotas/policies | `teams` list |
| Cluster provisioning | `charts/cluster-provisioning/` | ACM/Hive provisioning — see [Cluster Provisioning](../cluster-provisioning/) | `deployProvision: true` |

See [Chart categories](chart-categories.md) for detailed descriptions and chart listings.

## Key concepts

- **[conf.yaml](conf-yaml.md)** — the cluster identity file that controls which ApplicationSets generate Applications
- **[Values precedence](values-precedence.md)** — how chart defaults, environment-level, and cluster-level values merge
- **[The include pattern](values-precedence.md#the-include-pattern)** — every feature defaults to `include: false`, nothing deploys unless explicitly enabled
- **[ApplicationSet mechanics](applicationsets.md)** — matrix generators, boolean gates, elementsYaml

## Adding a chart to a cluster

1. Add the chart name to `platformCharts` or `operatorInstanceCharts` in the cluster's [conf.yaml](conf-yaml.md)
2. Set values in the corresponding file (`platform-config.yaml` or `operator-instances.yaml`)
3. Push to git — ArgoCD creates the Application and syncs it

## Removing a chart from a cluster

Remove the chart entry from `platformCharts` or `operatorInstanceCharts`. The Application is deleted, but `preserveResourcesOnDeletion` keeps the deployed resources intact on the target cluster.

## preserveResourcesOnDeletion

All 8 ApplicationSets set `preserveResourcesOnDeletion: true` at both the ApplicationSet and Application level. This means:

- Deleting a chart from `conf.yaml` removes the ArgoCD Application but **not** the resources on the target cluster
- Deleting the ApplicationSet itself removes Applications but preserves deployed resources
- This prevents accidental resource deletion from git changes

## Further reading

- [Day 2 cluster configuration guide](../day2-cluster-config/) — what to enable on each cluster, organized by priority tier
- [Cluster Provisioning](../cluster-provisioning/) — how clusters are provisioned with ACM/Hive (AWS, vSphere, baremetal, platform-none)
