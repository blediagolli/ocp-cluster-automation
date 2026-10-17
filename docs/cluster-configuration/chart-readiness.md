# Chart Readiness

[Category](chart-categories.md) says what a chart *does*. `oca.io/target` says *where it belongs*. This is the third axis, and the only one that is a claim about the past: **has this chart ever actually run?**

```yaml
annotations:
  oca.io/target: spoke
  oca.io/maturity: proven            # or: incubating
  oca.io/proven-on: my-cluster@2026-01-30
```

| Value | Meaning |
|---|---|
| `proven` | its objects have been applied to a real cluster and observed working. `oca.io/proven-on: <cluster>@<YYYY-MM-DD>` says where and when |
| `incubating` | everything else |

**Rendering, linting and review earn nothing here.** A chart is `incubating` until someone watched it work on a live cluster.

Every chart in this repo ships as `incubating`, because a claim about the cluster it was developed against is not evidence for yours. The annotation is yours to set as you prove each chart on your own estate — see [the promotion loop](#the-promotion-loop) below.

## Synced and Healthy is not proof

ArgoCD reporting `Synced/Healthy` means it applied the YAML it was given and the resulting objects look well-formed. It does not mean the chart did its job.

`ansible-automation-platform` is the case to keep in mind. Its Application can sit `Synced/Healthy` for weeks while `oc get ansibleautomationplatform -A` returns nothing: `templates/aap.yaml` is fine, but `aap.include` defaults to `false`, so the Application has only ever applied a Namespace, an OperatorGroup and a Subscription. Three objects, all healthy, and no Ansible.

`logging` is the same shape — live, with the `lokistack` CRD not even installed on the cluster.

This is structural, not a bug. Almost every operand in this repo sits behind an `include:` flag that defaults to `false` (see [the include pattern](values-precedence.md#the-include-pattern)), so an operator chart deployed with no values renders exactly its Subscription.

So the test for `proven` is **the operand, not the Application**. For an operator chart that means the CR it exists to create — `oc get <kind> -A` returning something — not `oc get csv`.

## Charts that only install an operator

Ten operator charts have no operand template at all. Five of those are finished and five are not, and the difference is invisible from the chart: both render a Namespace, an OperatorGroup and a Subscription, and stop.

So it is written down. A chart whose CR is supplied from outside declares where:

```yaml
oca.io/operand-from: cost-management-service/templates/dependencies/kafka.yaml
```

| Chart | Where its operand comes from |
|---|---|
| `amq-streams` | `cost-management-service/templates/dependencies/kafka.yaml` |
| `cloudnative-pg` | `cost-management-service/templates/dependencies/postgres.yaml` |
| `quay-bridge` | `quay/templates/quay-bridge.yaml` |
| `node-maintenance` | a `NodeMaintenance` is created per event, by a human |
| `openshift-pipelines` | the operator creates a default `TektonConfig` itself |

The other five have no such annotation because there is nothing to point at: **`dev-spaces`, `developer-hub`, `gitlab`, `gitlab-runner`, `jfrog`**. Each is a 43–48 line `values.yaml` of install scaffolding, and nothing in this repo renders their CR. Listing one gets an idle controller-manager pod and a CRD you would then have to `oc apply` into by hand — which this repo does not do. Treat them as unfinished, not as thin.

Check 8 below is what holds that line: the annotation becomes mandatory the moment such a chart claims `proven`. `scripts/validate-clusters.sh --charts` reads the same annotation to decide which live Applications are allowed to have applied nothing but a Subscription — which is why it is an annotation and not a list inside one of the scripts.

In the table below, the **Operand** column counts templates outside `templates/install/` and `templates/tests/`:

| Value | Meaning |
|---|---|
| *a number* | that many operand templates, every one behind an `include` flag that defaults to `false` — what the chart *can* render, not what it does |
| `N, always on` | at least one renders unconditionally |
| `elsewhere` | no operand template of its own, and `oca.io/operand-from` says why that is fine |
| `none` | no operand template, and nothing supplies one. The hollow five |

## What checks it

`make validate-chart-readiness` (in `make validate`; runs offline). Eight checks, all failing:

1. every chart has a `oca.io/maturity`, and it is `proven` or `incubating`
2. `proven` carries a well-formed `oca.io/proven-on`; `incubating` carries none
3. **no `clusterRegistered: true` cluster deploys an `incubating` chart**, unless that chart carries `oca.io/under-test: <that cluster>@<date>`
4. every `proven` chart is still deployed by some registered cluster, or is in the `GATED` table in `scripts/chart-readiness.sh`
5. the `GATED` table names only real charts
6. no `oca.io/under-test` claim is older than 30 days
7. no chart `HANDOFF.md` states a status of its own
8. a `proven` chart with no operand template of its own carries `oca.io/operand-from`

Check 3 is the load-bearing one. It is what keeps unproven charts off live clusters, and it replaces the obvious alternative — parking them on a long-lived branch — which would cost a permanent merge tax on the four byte-identical files under every `charts/operators/*/templates/install/` that `make validate-operator-install` compares, and which any `git checkout` undoes anyway.

Check 4 is the direction that stops this document rotting. `proven` would otherwise stay `proven` forever after a chart left the last live cluster's list.

Check 6 puts a clock on the escape hatch for the same reason. A chart under test is listable before it is proven, but only for thirty days, and the fix when it expires is to prove it or take it off the cluster — not to re-date the annotation.

Check 7 keeps per-chart status in one place. The rule is deliberately *not* "the `**Status:**` line in a chart's `HANDOFF.md` must agree with `oca.io/maturity`" — that is still a second copy of the fact, still needing an edit on every promotion, and still able to drift. A HANDOFF may only **point** at the annotation, with this exact line:

```
**Status:** see [chart readiness](../../../docs/cluster-configuration/chart-readiness.md); `oca.io/maturity` in `Chart.yaml` is the source of truth.
```

A pointer asserts nothing, so it cannot become wrong.

Check 8 is the one that came out of asking which charts "basically just install the operator". Ten do. The annotation is what separates the five that are finished from the five that are not, and making it mandatory for `proven` means a hollow chart cannot quietly acquire that label.

Offline checks can only enforce internal consistency — they cannot tell you a chart works. That needs a kubeconfig, and it is `make validate-chart-operands` (`scripts/validate-clusters.sh --charts`), kept out of `make validate` for that reason.

It reads each registered cluster's chart lists, finds the matching Application on the hub, and asks whether it applied anything beyond the `Namespace`/`OperatorGroup`/`Subscription` that every operator chart renders. A `proven` chart that applied only those three is a **SUBSCRIPTION-ONLY** failure, however green ArgoCD looks — unless it carries `oca.io/operand-from`. Run it before promoting a chart.

## The promotion loop

Prove charts on a cluster whose failure costs nothing, one at a time. Do not use the hub as a proving ground: a bad chart there can take out the ArgoCD doing the syncing.

1. `make render CLUSTER=<env>/<cluster> CHART=<x>`. **If it renders nothing it is not ready** — that is a values gap, not a chart that is done
2. set values in the cluster's `platform-config.yaml` or `operators.yaml` (or `operators/<x>.yaml` if large); re-render, and inspect the merged chain with `VALUES=1`
3. commit the `conf.yaml` entry together with `oca.io/under-test: <cluster>@<date>`, maturity still `incubating`. Check 3 permits it; check 6 starts the 30-day clock
4. watch it land: `oc get application -n openshift-gitops <app>`. Required is Synced + Healthy **and the operand genuinely up** — `oc get csv -n <ns>` plus the operand CR
5. commit the flip to `proven`, drop `under-test`, run `scripts/chart-readiness.sh --write`, confirm `make validate` is green

The split into two commits is the point. A dated annotation with an expiry is the only form of status that cannot quietly go stale.

## The table

<!-- BEGIN GENERATED: chart-readiness -->

| Chart | Group | Target | Maturity | Operand | Deployed on | Verified |
|---|---|---|---|---|---|---|
| `openshift-provisioning` | cluster-provisioning | hub | incubating | 28 | via `deployProvision` | — |
| `sushy-ec2-emulator` | cluster-provisioning | hub | incubating | 6, always on | — | — |
| `application-gitops` | onboarding | spoke | incubating | 4, always on | via `teams` | — |
| `namespace-config` | onboarding | spoke | incubating | 5 | via `teams` | — |
| `advanced-cluster-management` | operators | hub | incubating | 14 | — | — |
| `advanced-cluster-security` | operators | spoke | incubating | 14 | — | — |
| `amq-streams` | operators | spoke | incubating | elsewhere | — | — |
| `ansible-automation-platform` | operators | spoke | incubating | 1 | — | — |
| `cert-manager` | operators | spoke | incubating | 4 | — | — |
| `cloudnative-pg` | operators | spoke | incubating | elsewhere | — | — |
| `cluster-observability` | operators | spoke | incubating | 8 | — | — |
| `compliance` | operators | spoke | incubating | 3 | — | — |
| `cost-management-metrics` | operators | spoke | incubating | 3 | — | — |
| `cost-management-service` | operators | hub | incubating | 13 | — | — |
| `dev-spaces` | operators | spoke | incubating | none | — | — |
| `developer-hub` | operators | spoke | incubating | none | — | — |
| `external-secrets` | operators | spoke | incubating | 2 | — | — |
| `gatekeeper` | operators | spoke | incubating | 1 | — | — |
| `gitlab` | operators | spoke | incubating | none | — | — |
| `gitlab-runner` | operators | spoke | incubating | none | — | — |
| `group-sync` | operators | spoke | incubating | 1 | — | — |
| `jfrog` | operators | spoke | incubating | none | — | — |
| `keycloak` | operators | hub | incubating | 8 | — | — |
| `kyverno` | operators | spoke | incubating | 1 | — | — |
| `logging` | operators | spoke | incubating | 3 | — | — |
| `lvm` | operators | spoke | incubating | 1 | — | — |
| `metallb` | operators | spoke | incubating | 5 | — | — |
| `mtv` | operators | spoke | incubating | 1 | — | — |
| `nmstate` | operators | spoke | incubating | 1 | — | — |
| `node-feature-discovery` | operators | spoke | incubating | 1 | — | — |
| `node-maintenance` | operators | spoke | incubating | elsewhere | — | — |
| `oadp` | operators | spoke | incubating | 2 | — | — |
| `odf` | operators | spoke | incubating | 3 | — | — |
| `openshift-gitops` | operators | spoke | incubating | 5 | — | — |
| `openshift-local-storage` | operators | spoke | incubating | 1 | — | — |
| `openshift-pipelines` | operators | spoke | incubating | elsewhere | — | — |
| `openshift-virtualization` | operators | spoke | incubating | 1 | — | — |
| `opentelemetry` | operators | spoke | incubating | 1 | — | — |
| `portworx` | operators | spoke | incubating | 2 | — | — |
| `quay` | operators | hub | incubating | 5 | — | — |
| `quay-bridge` | operators | spoke | incubating | elsewhere | — | — |
| `servicemesh3` | operators | spoke | incubating | 6 | — | — |
| `tempo` | operators | spoke | incubating | 1 | — | — |
| `trident` | operators | spoke | incubating | 2 | — | — |
| `trusted-artifact-signer` | operators | spoke | incubating | 1 | — | — |
| `acm-managed-cluster` | platform-config | spoke | incubating | 5 | via `deployImport` | — |
| `admin-network-policy` | platform-config | spoke | incubating | 1 | — | — |
| `alertmanager-config` | platform-config | spoke | incubating | 1 | — | — |
| `etcd-backup` | platform-config | spoke | incubating | 1 | — | — |
| `etcd-defrag` | platform-config | spoke | incubating | 2 | — | — |
| `global-pull-secrets` | platform-config | spoke | incubating | 1 | — | — |
| `image-mirror-config` | platform-config | spoke | incubating | 1 | — | — |
| `image-pruner` | platform-config | spoke | incubating | 1 | — | — |
| `machine-health-checks` | platform-config | spoke | incubating | 1 | — | — |
| `openshift-apiserver` | platform-config | spoke | incubating | 1 | — | — |
| `openshift-build` | platform-config | spoke | incubating | 1 | — | — |
| `openshift-console` | platform-config | spoke | incubating | 3 | — | — |
| `openshift-dns` | platform-config | spoke | incubating | 1 | — | — |
| `openshift-group-sync` | platform-config | spoke | incubating | 3 | — | — |
| `openshift-image` | platform-config | spoke | incubating | 1 | — | — |
| `openshift-image-registry` | platform-config | spoke | incubating | 1 | — | — |
| `openshift-ingress` | platform-config | spoke | incubating | 1 | — | — |
| `openshift-machine-config` | platform-config | spoke | incubating | 9 | — | — |
| `openshift-marketplace` | platform-config | spoke | incubating | 2 | — | — |
| `openshift-oauth` | platform-config | spoke | incubating | 3, always on | — | — |
| `openshift-proxy` | platform-config | spoke | incubating | 1 | — | — |
| `openshift-scheduler` | platform-config | spoke | incubating | 1 | — | — |
| `project-request-template` | platform-config | spoke | incubating | 3 | — | — |
| `prometheus-rules` | platform-config | spoke | incubating | 1 | — | — |
| `rbac` | platform-config | spoke | incubating | 5 | — | — |
| `storage-classes` | platform-config | spoke | incubating | 1 | — | — |
| `tls-certificates` | platform-config | spoke | incubating | 3 | — | — |
| `user-workload-monitoring` | platform-config | spoke | incubating | 1 | — | — |
| `vault-server` | platform-config | hub | incubating | 9 | — | — |
| `volume-snapshot-classes` | platform-config | spoke | incubating | 1 | — | — |

0 proven, 75 incubating, 75 charts total.

<!-- END GENERATED -->

Regenerate with `scripts/chart-readiness.sh --write`. Every column is derived from `Chart.yaml` and `clusters/*/*/conf.yaml`, so no cell here is hand-maintained and none of it can drift from what ArgoCD reads.
