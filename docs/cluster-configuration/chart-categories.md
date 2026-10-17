# Chart Categories

All Helm charts are organized by category under `charts/`. Each category corresponds to an ApplicationSet that manages deployment.

## Where a chart is meant to run

Category says what a chart *does*. It does not say *where it belongs*, and those are different questions — `charts/platform-config/vault-server` sits in the platform-config directory alongside twenty-nine charts that every cluster runs its own copy of, and it is the one estate-wide service among them.

So every `Chart.yaml` carries a second, orthogonal axis:

```yaml
annotations:
  oca.io/target: hub      # or: spoke
```

| Value | Meaning |
|---|---|
| `hub` | belongs on the management hub — either its objects only function there (ManagedCluster, Hive, MultiClusterHub), or it *is* a shared service the other clusters consume |
| `spoke` | everywhere else, which in practice means anywhere. Most charts |

**There is deliberately no third "both" value.** Every cluster is a spoke, the hub included — ACM registers it as `local-cluster`, and it shows up in `oc get managedcluster` alongside the rest. So "runs anywhere" and "runs on a spoke" are the same statement, and a chart with no constraint is simply `spoke`.

That collapse is what makes the check one-directional: a `spoke` chart listed on the hub is correct, not a mismatch, so only a `hub` chart landing somewhere else is worth flagging.

Helm ignores annotations it does not recognise, so this changes nothing about rendering. It is metadata — read it before adding a chart to a `conf.yaml`, and `make validate-chart-targets` will warn if you get it wrong.

**The seven `hub` charts**, and why each one earns it:

| Chart | |
|---|---|
| `operators/advanced-cluster-management` | the MultiClusterHub is what makes a cluster the hub |
| `operators/cost-management-service` | the aggregator every cluster's metrics agent reports into |
| `operators/keycloak` | the estate's IdP; spokes' `openshift-oauth` and `openshift-group-sync` point at it |
| `operators/quay` | the estate's registry |
| `platform-config/vault-server` | the estate's secret backend; every spoke's ESO reads from it |
| `cluster-provisioning/openshift-provisioning` | Hive ClusterDeployment, hub-only by construction |
| `cluster-provisioning/sushy-ec2-emulator` | hub-side Redfish/BMC emulator serving provisioning |

The other 68 are `spoke`.

## Whether a chart has ever run

Category says what a chart does, `oca.io/target` says where it belongs, and neither says whether it works. That is a third annotation, `oca.io/maturity`, and it is the only one of the three that is a claim about the past:

```yaml
annotations:
  oca.io/target: spoke
  oca.io/maturity: incubating    # or: proven
```

Most of this repo is `incubating`, and `make validate-chart-readiness` stops a registered cluster deploying one without saying so. See [Chart readiness](chart-readiness.md) for the per-chart table and the reason `Synced/Healthy` does not count as proof.

**The annotation names the cluster a chart is *for*, which is not always where its manifests land.** `acm-managed-cluster` is the case to keep in mind. It is `spoke`: it registers a cluster that was deployed outside ACM, and that cluster is the subject. The objects happen to be applied on the hub, but that is the `cluster-import` ApplicationSet's doing — it pins `destination.server` to `https://kubernetes.default.svc` — not a property of the chart. Where a chart lands is already encoded in the two ApplicationSets that pin that field; the annotation answers the other question.

A corollary: **`acm-managed-cluster` still does not belong in any cluster's `platformCharts`.** `cluster-platform-config` renders to the cluster's own address, so listing it there would apply ManagedCluster CRs to the spoke itself. `deployImport: true` is the switch that imports a cluster.

The test for `hub` is whether something *consumes the instance across clusters*, not whether the hub happens to be the only cluster running it today. `ansible-automation-platform` is the useful counter-example: the hub runs one as part of the management plane, but nothing in this repo points at it from elsewhere, and two managed clusters already run their own — so it is `spoke`.

`advanced-cluster-security` is `spoke` for a different reason: one chart covers Central on the hub and SecuredCluster everywhere else, split by `include:` flags rather than by chart. `quay-bridge` and `cost-management-metrics` look hub-ish and are not — the hub lists both in its own `operatorCharts`, which is exactly the "the hub is a cluster too" case.

### What checks it

`make validate-chart-targets` (in `make validate`; runs offline). Three checks:

1. **fails** if a chart has no `oca.io/target`, or a value that is neither `hub` nor `spoke`
2. **fails** if a name in any `platformCharts`/`operatorCharts` has no chart directory — a typo'd chart name was silent before this, surfacing only when ArgoCD failed to render it
3. **warns** if a cluster that is not the hub lists a `hub` chart, deriving hub-ness the way `scripts/validate-clusters.sh` does: `cluster.address` of `https://kubernetes.default.svc` is the hub, anything else is not

Check 3 warns rather than fails because the labels are young and a debatable one should not block unrelated work. To promote it, change `warn=` to `fail=1` in the mismatch branch of `scripts/validate-chart-targets.sh`.

## Platform config (`charts/platform-config/`)

Day-2 platform configuration charts. Each chart manages a specific OpenShift subsystem — TLS, OAuth, API server settings, ingress, monitoring, RBAC, etc. Driven by the `platformCharts` list in `conf.yaml` and configured via `platform-config.yaml`.

Charts: `acm-managed-cluster`, `admin-network-policy`, `alertmanager-config`, `etcd-backup`, `etcd-defrag`, `global-pull-secrets`, `image-mirror-config`, `image-pruner`, `machine-health-checks`, `openshift-apiserver`, `openshift-build`, `openshift-console`, `openshift-dns`, `openshift-group-sync`, `openshift-image`, `openshift-image-registry`, `openshift-ingress`, `openshift-machine-config`, `openshift-marketplace`, `openshift-oauth`, `openshift-proxy`, `openshift-scheduler`, `project-request-template`, `prometheus-rules`, `rbac`, `storage-classes`, `tls-certificates`, `user-workload-monitoring`, `vault-server`, `volume-snapshot-classes`.

## Operators (`charts/operators/`)

One chart per operator, holding the OLM Subscription that installs it *and* the Custom Resources that configure it. Driven by the `operatorCharts` list in `conf.yaml` and configured via a shared `operators.yaml` plus an optional `operators/<chart>.yaml` at each level. `installOperators` in `conf.yaml` decides whether the Subscription half renders at all — false means this repo configures an operator that something else installed.

Listing a chart installs the operator and nothing else; each CR keeps its own `include: false` default.

Charts: `advanced-cluster-management`, `advanced-cluster-security`, `amq-streams`, `ansible-automation-platform`, `cert-manager`, `cloudnative-pg`, `cluster-observability`, `compliance`, `cost-management-metrics`, `cost-management-service`, `dev-spaces`, `developer-hub`, `external-secrets`, `gatekeeper`, `gitlab`, `gitlab-runner`, `group-sync`, `jfrog`, `keycloak`, `kyverno`, `logging`, `lvm`, `metallb`, `mtv`, `nmstate`, `node-feature-discovery`, `node-maintenance`, `oadp`, `odf`, `openshift-gitops`, `openshift-local-storage`, `openshift-pipelines`, `openshift-virtualization`, `opentelemetry`, `portworx`, `quay`, `quay-bridge`, `servicemesh3`, `tempo`, `trident`, `trusted-artifact-signer`.

Replaces the former `charts/operator-deployment` (one chart, all Subscriptions, gated by `deployOperators`) and `charts/operator-instances` (a second chart per operand, gated by `operatorInstanceCharts`). See [Merged operator charts](merged-operator-charts.md) for why, and what every chart shares.

## Onboarding (`charts/onboarding/`)

Team onboarding charts. The `teams` list in `conf.yaml` drives these — each team gets:

- **application-gitops** — the team's own ArgoCD instance, plus an AppProject scoped to its repos and namespaces, and RBAC on the `<team>-gitops` namespace
- **namespace-config** — namespaces with ResourceQuotas, LimitRanges, baseline NetworkPolicies, and admin/view RoleBindings, plus an optional ClusterResourceQuota capping the team's total across them

Either half can be switched off per team, per cluster, with
`applicationGitops: false` or `namespaceConfig: false` on the entry. Absent
means on. Most teams want namespaces without a dedicated ArgoCD instance —
five pods per team adds up — and the switch lives in `conf.yaml` rather than
`teams/<team>.yaml` because the answer differs by cluster: a team may run its
own ArgoCD in dev and deploy to prod from the central one.

Switching a half off is **not** a retirement. It deletes the Application, and
`preserveResourcesOnDeletion: true` then strands everything that Application
owned — the same trap as removing the team from the list.

The ResourceQuota and LimitRange are each switchable, per size tier and per
namespace, so an existing estate can come under this chart before it comes
under its enforcement. Switching one off on a namespace that already has it
*deletes* the live object — `prune: true` — so the direction to run a migration
in is tier off, namespaces opted back in one at a time.

A size tier is a **per-namespace** figure, so it cannot cap a team: five
`small` namespaces is five times `small`. `clusterResourceQuota.hard` adds a
cluster-scoped `<team>-cluster-quota` summed across every namespace the team
owns on that cluster — a ceiling over the tiers rather than one of them, with
both enforced and the most restrictive winning. It is **off by default**,
because the right total depends on the cluster's capacity and on how many
namespaces the team owns there, and switching it on for a team already running
near the sum of its tiers rejects the next pod it schedules. See
`charts/onboarding/namespace-config/HANDOFF.md`.

Retiring a team is **one flag**, set in `teams/<team>.yaml` for every cluster
or `clusters/<env>/<cluster>/teams/<team>.yaml` for one:

| | `namespace-config` renders | `application-gitops` renders | Reversible |
|---|---|---|---|
| normal | everything | everything | — |
| `team.quiesce: true` | namespaces, quota, limits, NetworkPolicies; **no RoleBindings, no `managed-by`** | `<team>-gitops` and nothing in it | yes |

Quiesce is "decommissioned": the team cannot reach its namespaces and its
ArgoCD cannot deploy into them, but the namespaces and every PVC in them
survive, labelled `oca.io/lifecycle: quiesced`. It does not stop pods already
running — scale those down first if that matters.

**Neither chart will ever render nothing**, in any state. That is deliberate
and it is why there is no second flag: an empty render is indistinguishable
from a deleted values file, so the charts treat it as one and fail. It also
sidesteps two ArgoCD behaviours that make "sync to empty" unreliable in
practice — see `charts/onboarding/namespace-config/HANDOFF.md`.

So **deleting a tenancy is a deliberate manual step**, not something a commit
can do by itself:

1. `team.quiesce: true`, let it sync, confirm the team's ArgoCD is gone
2. remove the team's entry from the cluster's `conf.yaml`
3. `oc delete ns -l app.kubernetes.io/part-of=<team>`

Step 3 deletes every PVC in those namespaces, and a PV with the default
`Delete` reclaim policy takes the underlying volume with it.

Note that step 2 on its own is **not** a retirement — it deletes the
Application, and `preserveResourcesOnDeletion: true` strands everything it
owned, running and unmanaged. Quiesce first.

## Cluster provisioning (`charts/cluster-provisioning/`)

Covered in the [Cluster Provisioning](../cluster-provisioning/) guide.
