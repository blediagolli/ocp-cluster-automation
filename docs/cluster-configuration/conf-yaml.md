# conf.yaml Structure

The `conf.yaml` file is the cluster identity. It controls which ApplicationSets generate Applications for this cluster.

## Example

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

## Fields

| Field | Type | Description |
|---|---|---|
| `cluster.name` | string | Cluster name — used in Application names and as the ArgoCD destination |
| `cluster.environment` | string | Environment (dev, prod, mgt) — matches the directory under `clusters/` and `env/` |
| `cluster.address` | string | Kubernetes API endpoint (usually the cluster-proxy-addon URL for managed clusters) |
| `cluster.baseDomain` | string | Base domain for the cluster |
| `platformCharts` | list | Charts from `charts/platform-config/` to deploy — each entry is `{chart: <name>}` |
| `operatorInstanceCharts` | list | Charts from `charts/operator-instances/` to deploy — each entry is `{chart: <name>}` |
| `deployOperators` | bool | Gate for the operator-deployment chart (OLM Subscriptions) |
| `deployOverlay` | bool | Gate for cluster-specific raw manifest overlays |
| `deployImport` | bool | Gate for ACM cluster import (ManagedCluster + KlusterletAddonConfig) |
| `deployProvision` | bool | Gate for ACM/Hive cluster provisioning |
| `teams` | list | Teams to onboard — each entry is `{team: <name>}` |

## Adding a chart to a cluster

1. Add the chart name to `platformCharts` or `operatorInstanceCharts`
2. Set values in the corresponding file (`platform-config.yaml` or `operator-instances.yaml`)
3. Push to git — ArgoCD creates the Application and syncs it

All chart features default to `include: false` — see [The include pattern](values-precedence.md#the-include-pattern).

## Removing a chart from a cluster

Remove the chart entry from `platformCharts` or `operatorInstanceCharts`. The Application is deleted, but `preserveResourcesOnDeletion` keeps the deployed resources intact on the target cluster.

## Cluster directory layout

Each cluster is defined by a directory under `clusters/<env>/<name>/` containing:

```
clusters/dev/aws-test/
  conf.yaml                # cluster identity and chart lists (this file)
  platform-config.yaml     # values for platform-config charts
  operator-instances.yaml  # values for operator CR charts
  operator-deployment.yaml # values for operator Subscriptions
  provision.yaml           # provisioning values (if deploying a new cluster)
```

Not all files are required — `ignoreMissingValueFiles: true` means absent files are silently skipped. At minimum, a cluster needs `conf.yaml`.
