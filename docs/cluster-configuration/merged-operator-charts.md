# Merged operator charts

Status: merged to `main` and live on acm-hub as of 2026-10-08. All 40 operators
migrated, `charts/operator-deployment` and `charts/operator-instances` deleted.
The hub's 17 operator Applications are Synced and Healthy; the four managed
clusters are gated off by `clusterRegistered: false` until they are imported.

## The problem

Three complaints that all read as "the operators Application is hard to follow":

1. **One Application, all operators.** `cluster-operators` rendered
   `charts/operator-deployment` once per cluster — 18 enabled operators on
   acm-hub, ~50 resources in one flat sync unit. One unresolvable channel
   degraded the whole thing and there was no per-operator health.
2. **One operator spanned three files.** Keycloak needed `operators.keycloak` in
   `operator-deployment.yaml`, `operatorInstanceCharts: - chart:
   keycloak-instance` in `conf.yaml`, and ~180 lines of `keycloak:`/`postgres:`/
   `realm:` in `operator-instances.yaml`. Nothing checked that the three agreed.
3. **Every instance Application got every chart's values.**
   `operator-instances.yaml` was 647 lines and the ApplicationSet passed all of
   it to all 15 charts.

And underneath: install-before-CR ordering was never modelled. It worked by
`selfHeal` retry churn plus hand-written CRD-wait hook Jobs.

## The shape

One chart per operator under `charts/operators/<name>/`, holding the
Subscription *and* the CRs. One Application each, named
`op-<env>-<cluster>-<operator>`, from the single `cluster-operators`
ApplicationSet.

```
charts/operators/keycloak/
  templates/
    install/                  # identical in all 40 charts
      _operator.tpl
      namespace.yaml          # wave -30
      operatorgroup.yaml      # wave -29
      subscription.yaml       # wave -28
    postgres/                 # wave -10 / -5
    keycloak.yaml             # wave   0
    realm/                    # wave   1 / 9 / 10
```

Helm loads `templates/` recursively and ignores the directory a file sits in —
`define` names and `_*.tpl` helpers are path-independent, and the rendered
output is unchanged — so the subdirectories cost nothing and exist purely for
reading the chart. `install/` is in all 40. Beyond that a chart only splits
when it holds two separately-enabled operands: ACS into `central/` and
`secured-cluster/`, ACM into `multiclusterhub/` and `observability/`, logging
into `lokistack/` and `log-forwarder/`. Single-operand charts stay flat, and
anything shared between groups sits in the base directory.

The install block sits below every wave any instance chart used, which is why
no chart's existing ladder had to be re-laid when it was merged. An earlier
draft put it at -10/-9/-8 and pushed Keycloak's Postgres down a wave to stop it
racing its own namespace; moving the install block down instead let that ladder
go back to exactly what `keycloak-instance` shipped.

This page is the reference for the pattern. Each chart's `values.yaml` is the
reference for that operator's own CRs — it is commented and sits next to the
templates that read it.

### `extraOperators`

A namespace with two OperatorGroups fails every CSV in it, so a capability that
needs a second operator in the same namespace declares it under
`extraOperators` rather than as a chart of its own. Same keys as `operator:`,
but it renders a Subscription and nothing else. Used by `logging`
(loki-operator) and `servicemesh3` (kiali-ossm).

Those two are the only charts carrying
`templates/install/extra-subscriptions.yaml` and an `extraOperators` values
key. It is the one install template that is not universal — everywhere else it
rendered nothing, so it is not shipped there. The template and the values key
have to travel together: a template with no key is dead code, and a key with
no template is worse, because setting it would render nothing and report
nothing. `make validate-operator-install` fails on either half alone, and also
scans every file in the values chain, so setting `<chart>.extraOperators` in a
cluster's `operators.yaml` for one of the other 38 is caught at validation
rather than discovered as a Subscription that never appeared.

### Adding an operator

1. `cp -r` an ordinary chart's `templates/install/` directory — `cert-manager`
   is the reference copy: `_operator.tpl`, `namespace.yaml`,
   `operatorgroup.yaml`, `subscription.yaml`. They are byte-identical
   everywhere and must stay that way; `make validate-operator-install`
   enforces it. Only add `extra-subscriptions.yaml` if the operator needs a
   second Subscription in its namespace.
2. `Chart.yaml` with `name:` matching the directory.
3. `values.yaml` with `installOperators: true` at the top level, and everything
   else nested under the chart name: an `operator:` block, `namespace: ""`,
   `createNamespace: false`, then one block per CR, each with `include: false`.
4. Add the CR templates, in `templates/` or in a subdirectory per operand. Each
   starts `{{- $v := index .Values .Chart.Name }}` and gates on
   `$v.<block>.include`. A `define` block is a separate scope — a file-level
   `$v` is not visible inside one.
5. Add the chart to `operatorCharts` in the clusters that want it.

`make validate-operators` lints every chart and renders each one through the
same six-file chain the ApplicationSet uses, for every cluster that lists it.
`make validate-operator-install` checks the shared install templates still
match. Both run under plain `make validate`.

## Where the values go

One file per operator isolates values nicely and produces 18 files in a
directory; one shared file per level keeps the directory legible and gets long.
The repo does both and lets each operator pick.

```
clusters/mgt/acm-hub/
  conf.yaml                   # operatorCharts: 17 entries
  operators.yaml              # 9 small operators, a few settings each
  operators/keycloak.yaml     # keycloak: — ~190 lines, own file
  operators/quay.yaml, odf.yaml, advanced-cluster-*.yaml, ...
```

Chain, later winning, all optional via `ignoreMissingValueFiles`:

```
chart defaults
  → env/<env>/operators.yaml
  → env/<env>/operators/<operator>.yaml
  → clusters/<env>/<cluster>/operators.yaml
  → clusters/<env>/<cluster>/operators/<operator>.yaml
```

**The price is that every chart nests its values under its own name** —
`keycloak.operator.channel`, not `operator.channel`. Without that, two operators
in one shared file would both write a top-level `operator:` and the last one
would win. The payoff: the shape is identical in both places, so promoting an
operator out of the shared file into its own is a cut-and-paste, not a rewrite.

acm-hub ended up with 9 files where it had 2 very large ones, and no file longer
than keycloak's.

Layout does **not** affect ArgoCD sync churn — ArgoCD re-renders every
Application on any repo change and compares rendered output, so a shared file
does not cause spurious syncs. What it does affect is the blast radius of a YAML
syntax error: a broken `operators.yaml` fails every operator's render, a broken
`operators/keycloak.yaml` fails one.

## What the migration established

**It renders identically.** Verified resource by resource on all five clusters:
old pipeline and new produce the same inventory, and no field differs outside
`# Source:` comments, the new sync-wave annotations, the Application-level sync
option, and the `operator:` label — which follows `.Chart.Name` and so changed
from the OLM package name to the chart name on the handful of charts where the
two differ (`compliance-operator` → `compliance`, `odf-operator` → `odf`,
`openshift-logging` → `logging`, `external-secrets-operator` → `external-secrets`).

**The ordering works, and it is the real prize.** ArgoCD's built-in health check
for `Subscription` gates on `status.state: AtLatestKnown`, so a wave -28
Subscription blocks wave 0 until the CSV is installed and the CRDs are
registered. No CRD-wait Job needed. The existing ones were left in place: they
are harmless and still cover `installOperators: false`.

**Waves order the apply, not the dry-run.** On a cluster that has never had the
operator, comparison fails with `no matches for kind "Keycloak"` before any wave
runs. `SkipDryRunOnMissingResource=true` is set once in the ApplicationSet's
`syncPolicy.syncOptions` rather than annotated onto every CR in forty charts.

**`.Values.<chart-name>` is not a valid Go template expression** when the chart
name has a hyphen. Every template starts
`{{- $v := index .Values .Chart.Name }}` instead, which also makes the install
templates byte-identical across all 40 charts — closing the "duplicated
boilerplate" question without a library chart, because there is nothing
per-chart left to parameterise. Watch for `define` blocks: they are a separate
scope and a file-level `$v` is not visible inside one.

Duplication is only safe if drift is detectable, and for most of the migration
it was not: the five files sat interleaved with each chart's own templates with
nothing marking them as shared. Collecting them into `templates/install/` made
the rule checkable, and `make validate-operator-install` now compares all five
against `cert-manager`'s copies and fails on any difference.

**`deployOperators` was load-bearing in a way that nearly broke the migration.**
It gated the whole old operators Application, and four of five clusters set it
false — their Subscriptions were not repo-managed at all, only their CRs.
Merging naively would have started installing operators on live managed
clusters. It became `installOperators` in `conf.yaml`, gating the install half
of every chart instead of a whole Application.

**Merging removed a second switch, and some values had been relying on it.**
A CR used to need both its own `include:` flag *and* its chart listed in
`operatorInstanceCharts`. Several blocks in acm-hub's `operator-instances.yaml`
said `include: true` for a chart that was never listed — they read as enabled
and were inert. Those flags are now `false`, with a comment at each one.

**`missingkey=error` means the new key must exist everywhere.** A map lookup
fails before any `| default` can run, so all five `conf.yaml` files declare
`operatorCharts` and `installOperators`, empty or false where unused.

## Things found on the way

- **Two OperatorGroups in one namespace fail every CSV in it.**
  `operator-deployment` rendered one per `operators:` entry, so enabling both
  `openshift-logging` and `loki` broke both. Second operators in a shared
  namespace now go through `extraOperators`, which renders a Subscription and
  nothing else.
- **Helm test Pods collided** when two instance charts folded into one release —
  the second silently overwrote the first. ACM's and ACS's are renamed.
- **The one CatalogSource** moved out of `operator-deployment`'s shared
  `catalogSources` map into `charts/operators/cost-management-service`, at wave
  -31. It used to depend on a different Application having synced first, with
  nothing expressing the order.
- **OADP had no Subscription anywhere.** Two instance charts configured an
  operator that nothing in this repo installed. One was added; no cluster
  enables it.
- **`namespaceLabels`/`namespaceAnnotations`** existed in `operator-deployment`'s
  defaults for exactly one operator, ACM. Easy to drop in a bulk migration, and
  dropping them would have quietly removed `openshift.io/cluster-monitoring`
  from the hub's namespace.

## Still open

- **When does an operator earn its own file?** The rule is "when it would drown
  the shared file" and nothing enforces it. keycloak at ~190 lines clearly
  qualifies and cloudnative-pg at one setting clearly does not; the middle is a
  judgement call.
- **The wave ladder is still unproven.** acm-hub synced cleanly, but every one
  of its 110 resources already existed, so the first sync installed nothing.
  The Subscription health check gating wave 0 is still reasoned from ArgoCD's
  shipped health checks rather than observed. It only gets exercised on a
  cluster where an operator is genuinely absent — which needs one of the four
  managed clusters imported and `clusterRegistered` turned on.
