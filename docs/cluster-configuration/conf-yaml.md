# conf.yaml Structure

The `conf.yaml` file is the cluster identity. It controls which ApplicationSets generate Applications for this cluster.

## Example

```yaml
cluster:
  name: example-cluster
  environment: dev
  address: "https://cluster-proxy-addon-user.multicluster-engine.svc.cluster.local:9092/example-cluster"
  baseDomain: example.com

# Charts to deploy
platformCharts:
  - chart: tls-certificates
  - chart: openshift-apiserver
  - chart: openshift-ingress
  - chart: openshift-proxy
  - chart: etcd-backup
  - chart: openshift-oauth

operatorCharts:
  - chart: cert-manager
  - chart: advanced-cluster-security

# Whether the operator charts install their operators, or only configure
# operators that something else put there.
installOperators: true

# Whether ArgoCD can actually reach this cluster. False until it is imported.
clusterRegistered: true

# Boolean gates
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
| `operatorCharts` | list | Charts from `charts/operators/` to deploy — each entry is `{chart: <name>}`. A chart installs its operator *and* renders its CRs |
| `installOperators` | bool | Whether the charts above render their Namespace, OperatorGroup and Subscription. `false` keeps only the CRs — for clusters whose operators are installed by an ACM policy or by hand |
| `clusterRegistered` | bool | Whether ArgoCD can resolve this cluster's destination. `false` makes every ApplicationSet that targets the cluster generate nothing for it. See below |
| `deployOverlay` | bool | Gate for cluster-specific raw manifest overlays |
| `deployImport` | bool | Gate for ACM cluster import (ManagedCluster + KlusterletAddonConfig) |
| `deployProvision` | bool | Gate for ACM/Hive cluster provisioning |
| `teams` | list | Teams to onboard — each entry is `{team: <name>}` |

## `clusterRegistered`

A cluster can be fully described here long before it exists. Without a gate,
the ApplicationSets generate Applications for it anyway, pointing at a
destination ArgoCD has never heard of:

```
application destination spec is invalid: error getting cluster by server
"https://cluster-proxy-addon-user.multicluster-engine.svc.cluster.local:9092/<name>":
cluster ... not found
```

That failure is not scoped to the one Application. It fails the whole
ApplicationSet, which stops it reconciling for *every* cluster and shows up as
a Degraded `platform-root`. One unimported cluster takes the fleet's status
with it.

`clusterRegistered: false` makes each generator's `elementsYaml` yield `[]`
for that cluster, so no Application is generated and there is no destination
to resolve. Set it `true` once the cluster is imported and has a cluster
secret in `openshift-gitops`. The hub's own entry is `true` because its
destination is the in-cluster `https://kubernetes.default.svc`, which is
always resolvable.

`cluster-import` and `cluster-provisioning` deliberately ignore the flag —
they run against the hub to bring the cluster into existence, so gating them
on the cluster already existing would deadlock.

Because the flag is a hand-maintained claim about the world, it goes stale.
`make validate-clusters` compares it against the live hub and fails on either
direction of disagreement. It needs a kubeconfig, so it is not part of plain
`make validate`.

## Adding a chart to a cluster

1. Add the chart name to `platformCharts` or `operatorCharts`
2. Set values in the corresponding file — `platform-config.yaml`, or `operators.yaml` / `operators/<chart>.yaml`
3. Push to git — ArgoCD creates the Application and syncs it

All chart features default to `include: false` — see [The include pattern](values-precedence.md#the-include-pattern).

## Removing a chart from a cluster

Remove the chart entry from `platformCharts` or `operatorCharts`. The Application is deleted, but `preserveResourcesOnDeletion` keeps the deployed resources intact on the target cluster.

## Cluster directory layout

Each cluster is defined by a directory under `clusters/<env>/<name>/` containing:

```
clusters/dev/example-cluster/
  conf.yaml                # cluster identity and chart lists (this file)
  platform-config.yaml     # values for platform-config charts
  operators.yaml           # values for several operators, shared
  operators/<chart>.yaml   # values for one operator, when it outgrows the above
  provision.yaml           # provisioning values (if deploying a new cluster)
```

Not all files are required — `ignoreMissingValueFiles: true` means absent files are silently skipped. At minimum, a cluster needs `conf.yaml`.
