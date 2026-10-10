# Chart Categories

All Helm charts are organized by category under `charts/`. Each category corresponds to an ApplicationSet that manages deployment.

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
- **namespace-config** — namespaces with ResourceQuotas, LimitRanges, baseline NetworkPolicies, and admin/view RoleBindings

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

Retiring a team is **one flag**, set in `teams/<team>.yaml` for every cluster
or `clusters/<env>/<cluster>/teams/<team>.yaml` for one:

| | `namespace-config` renders | `application-gitops` renders | Reversible |
|---|---|---|---|
| normal | everything | everything | — |
| `team.quiesce: true` | namespaces, quota, limits, NetworkPolicies; **no RoleBindings, no `managed-by`** | `<team>-gitops` and nothing in it | yes |

Quiesce is "decommissioned": the team cannot reach its namespaces and its
ArgoCD cannot deploy into them, but the namespaces and every PVC in them
survive, labelled `gfo.io/lifecycle: quiesced`. It does not stop pods already
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
