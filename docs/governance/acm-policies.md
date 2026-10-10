# ACM Policies

**Status:** implemented. Policies live in `policies/` at the repo root as
PolicyGenerator directories, rendered by an ArgoCD ConfigManagementPlugin and
delivered by the `hub-acm-policies` ApplicationSet. The `acm-policies` Helm
chart this document originally described was never deployed and has been
deleted — see [Architecture](#architecture) for what replaced it and why.

Hub is ACM 2.17.3.

## The decision

**Policies attest. ArgoCD configures.**

Every policy runs `remediationAction: inform`. A policy's job is to answer
"does the fleet hold this property?" — never to make it true. Charts make it
true, through the ApplicationSets that already reach every managed cluster.

```
ArgoCD chart  ──writes──>  NetworkPolicy on the cluster
ACM Policy    ──reads───>  "is it there?"          inform
```

### Why not enforce

This repo is not a bare ACM hub. `acm-managed-cluster` writes an ArgoCD
cluster secret for every imported cluster, and the ApplicationSets deploy
charts straight to them. Anything a policy could enforce, a chart already
deploys.

So an enforcing policy is a *second writer* on objects ArgoCD owns. Two
controllers with independent reconcile loops and no shared notion of
desired state will fight: ArgoCD syncs the chart's version, the policy
controller overwrites it, ArgoCD marks the app OutOfSync and syncs again.
The object flaps, both controllers report success, and git stops describing
what is on the cluster.

The deleted sketch contained two instances of this. Its `network-isolation`
policy was `enforce` and overlapped the `admin-network-policy` chart; its
`compliance-operator` policy was `enforce` and overlapped the `compliance`
operator chart. Neither was ever deployed, so neither bit.

Inform-only avoids the whole class of problem, and it is the more useful
mode anyway: a failing inform policy is a **drift alarm**. It says a cluster
diverged from git — which is exactly the thing you want paged about, and
exactly the thing an enforcing policy hides by silently repairing it.

### The one exception

Enforcement is reserved for objects **no chart reaches**. Exactly one
qualifies today: `policies/stable/cluster-labels`, which stamps the `gfo.io/*`
labels onto `ManagedCluster` objects.

It qualifies because ArgoCD is structurally barred from that field.
`clusters/mgt/acm-hub/applicationsets/cluster-import.yaml` carries

```yaml
ignoreDifferences:
  - group: cluster.open-cluster-management.io
    kind: ManagedCluster
    jsonPointers:
      - /metadata/labels
```

so ArgoCD will not reconcile `ManagedCluster` labels even where it owns the
object — and for `local-cluster` it does not own the object at all, because
ACM creates that one itself. There is no second writer to fight. An inform
policy here would report "the label is missing" forever with nothing able to
act on it, which is a defect report, not a control.

This is the shape every future exception has to have: not "enforcing is more
convenient", but *a demonstration that no chart can write the object*. The
policy carries a comment saying what would retire it. Enforcement without that
justification is a bug.

Note that `Policy.spec.remediationAction` overrides the child policy's, so
`cluster-labels` pins `enforce` in its `policy-generator-config.yaml` rather
than taking the `${REMEDIATION}` token the ApplicationSet sets to `inform`.

## Ownership

One writer per object, and the writer is always a chart.

| Property attested | Policy (reads) | Chart that writes it |
|---|---|---|
| Pod Security Standards labels on namespaces | `pod-security` | `project-request-template` |
| Default-deny NetworkPolicy in tenant namespaces | `network-isolation` | `namespace-config`, `admin-network-policy` |
| ResourceQuota present in tenant namespaces | `resource-quota` | `namespace-config` |
| Compliance Operator installed and current | `compliance-operator` | `compliance` |
| Container images from allowed registries only | `image-registries` | `openshift-image` |
| etcd encryption enabled | `etcd-encryption` | `openshift-apiserver` |

Read that table as the contract. If a policy has no chart in the right-hand
column, either the chart is missing or the policy is enforcing something
nobody owns — both are defects, and the table is where they show up.

The two tenant-namespace rows said `project-request-template` until the
onboarding charts were hardened, and that was wrong in a way worth recording.
That chart is wired as the cluster's
`project.config.openshift.io/cluster .spec.projectRequestTemplate`, which the
API server expands **only on the project request path** — `oc new-project` and
the console's Create Project. A plain `kind: Namespace`, which is what
`namespace-config` applies, bypasses it completely. So every team namespace
created by the onboarding ApplicationSet had no NetworkPolicy and no
ResourceQuota from that chart, and never would have: `network-isolation` was
reporting a real gap against a writer that could not reach the objects.
`namespace-config` now writes both, with the NetworkPolicy bodies kept
identical to `project-request-template`'s so the two paths agree.

`pod-security` still points at `project-request-template` and is still
narrower than it looks, for the same reason — tenant namespaces do not get
Pod Security labels from the onboarding charts. That is a known gap rather
than a mislabelled one.

These six are grouped by the `security-baseline` PolicySet
(`policies/stable/policy-framework/policyset.yaml`) so compliance rolls up to
one status instead of six.

Three directories are not controls and are not members of that set:

| Directory | What it is |
|---|---|
| `policy-framework` | The namespace, the `ManagedClusterSetBinding`, and the PolicySet itself |
| `cluster-config-maps` | The ConfigMaps the hub templates read per-cluster values from |
| `cluster-labels` | The one enforcing policy — see [the exception](#the-one-exception) |

Because the attested values must match what the charts write byte for byte,
several manifests are copies with a `# Written by:` header naming their
source. A drift between the two files produces a false non-compliance rather
than a caught one, so those headers are load-bearing: change the chart,
change the policy.

## Placement

Policies bind to **ManagedClusterSets**, not to label selectors.

The deleted sketch selected on `environment in (production, staging)` and
`vendor in (OpenShift)`. That does not work here, and the way it fails is
the reason this section exists.

### The silent-inert failure mode

`local-cluster` — the hub, and currently the fleet's only ManagedCluster —
carries no `environment` label. ACM creates that object itself, so the
`acm-managed-cluster` chart, which *does* set `environment`, never touches
it. Four of the six policies would therefore select **zero clusters**.

A policy with no placement decisions reports **Compliant**. It is
indistinguishable on the dashboard from a policy that genuinely passes
everywhere. A governance control that is silently inert is worse than no
control, because it is believed.

Label selectors invite this: the policy is correct, the label is missing,
and nothing connects the two. Cluster set membership is explicit — a cluster
is in the set or it isn't, and an empty set is visible as an empty set.

### The model

```
ManagedClusterSet: default
  └─ ManagedClusterSetBinding  ──> open-cluster-management-policies
     └─ Placement              ──> all clusters in the set
        └─ PlacementBinding    ──> Policy
```

Three facts about the current hub that this accounts for:

- The only cluster sets are `default` and `global`. `local-cluster` is in
  `default`, so `policy-framework` binds `default` and only `default`. Binding
  a set that does not exist is the silent-inert failure in another costume.
- The binding lives in `open-cluster-management-policies`, the namespace
  `policy-framework` creates. Before that binding existed, bindings were
  present only in `openshift-gitops` and `open-cluster-management-global-set`.
  A `Placement` cannot see a single cluster until the binding is in its own
  namespace — it is not optional wiring.
- The hub must be governed too. `local-cluster` is in `default`, so the
  cluster running the management plane is audited like any other.

The placements carry no label predicates: a cluster in a bound set is in
scope. Each scaffolded `placement.yaml` includes a commented example of a
label predicate for the case where a policy genuinely needs to be narrower,
but narrowing by default is how you arrive at a policy that selects nothing.

The binding is **per policy**, not per PolicySet. Each directory ships its own
`Placement` and `PlacementBinding`, which is what lets a directory be added or
removed without editing anything else. The `security-baseline` PolicySet is
therefore deliberately *unbound* — it aggregates status for the console, and
binding it as well would place every member twice.

## Architecture

Policies are **not** a Helm chart. They are PolicyGenerator directories
rendered by kustomize inside an ArgoCD ConfigManagementPlugin.

```
policies/stable/<name>/
  kustomization.yaml            marker file; the ApplicationSet globs for it
  policy-generator-config.yaml  what to wrap, how, and with what metadata
  placement.yaml                who it applies to
  manifests/                    plain Kubernetes YAML — the thing attested
  README.md

        │
        │  hub-acm-policies ApplicationSet  (files: policies/*/*/kustomization.yaml)
        ▼
  one Argo Application per directory, plugin: policy-generator
        │
        │  CMP sidecar on the repo-server:
        │    sed the ${TOKEN}s, then
        │    kustomize build --enable-alpha-plugins
        ▼
  Policy + Placement + PlacementBinding, in open-cluster-management-policies
```

### Why the tree sits at the repo root

`policies/` and `policy-values/` are top-level, not under
`clusters/mgt/acm-hub/`, even though the hub is the only cluster that hosts
them. The question comes up because the delivery side *is* hub-specific — the
ApplicationSet lives in `clusters/mgt/acm-hub/applicationsets/`.

`clusters/<env>/<cluster>/` in this repo means **configuration applied _to_
that cluster**: `operators.yaml`, `platform-config.yaml` and `overlay/` are all
read by charts whose Argo destination is that cluster. A policy is not acm-hub's
configuration. It is fleet governance the hub happens to host — destination
`open-cluster-management-policies`, Placement scoped to a clusterset, and a
verdict about every member of that set. Filing it under one cluster conflates
delivery with subject, the same way putting it in `platform-config.yaml` would
(see the pointer at `docs/reference/platform-config.yaml`).

The move itself would be cheap — a glob, a path segment index, a line in
`scripts/generate-policy.sh`, two in the `Makefile`, and some prose. What makes
it a bad trade is the trap on the other side: `make validate-hub` runs
`oc kustomize clusters/mgt/acm-hub`, and `oc kustomize` has no
`--enable-alpha-plugins`. Nine PolicyGenerator directories under that path are
nine directories that build everywhere except in the one command CI-adjacent
tooling runs, waiting for someone to add `- policies` to that `resources:` list.
That is why `clusters/mgt/acm-hub/kustomization.yaml` carries a comment saying
there is deliberately no `policies` entry, and why the empty overlay that used
to sit there was deleted rather than kept as a stub.

### Why not a Helm chart

Helm's `{{ }}` and ACM's `{{hub ... hub}}` are the same delimiters. Any hub
template written in a Helm chart has to be escaped past Helm's parser, and the
escaping is where the bugs live. Beyond that, wrapping manifests in Policy CRs
is a solved problem: PolicyGenerator is the tool Red Hat ships for it, so
hand-writing the wrapper is a reimplementation that has to be kept current
with an API someone else owns.

With PolicyGenerator, authoring a policy means writing the plain Kubernetes
object you want to attest and letting the generator wrap it. The six
`manifests/` files in this repo are exactly that — ordinary YAML, readable
without knowing anything about ACM.

### Why a CMP, and what it costs

PolicyGenerator is a kustomize **exec plugin**, not a CRD. It cannot run
inside a Helm render, and `oc kustomize` cannot run it either — there is no
`--enable-alpha-plugins` flag on `oc`. Something has to run real `kustomize`
with the plugin binary on disk.

The two options are generating the YAML at build time and committing it, or
running the generator in the repo-server. This repo does the second, so that
git holds the authored policy rather than its output.

The cost is real and worth stating: **it modifies the ArgoCD that manages the
entire fleet**. `clusters/mgt/acm-hub/bootstrap/openshift-gitops/instance/`
gains an init container that lifts the `PolicyGenerator` binary out of the ACM
image, a sidecar running `argocd-cmp-server`, and the plugin ConfigMap. Both
images are digest-pinned, with the commands to refresh them in a comment.

A CMP failure surfaces in Argo as an opaque `ComparisonError`. `make
validate-policies` exists to make that unnecessary: it reproduces the CMP's
exact token substitution and build locally, so a broken directory is caught
before it reaches the repo-server.

### Tokens, not a template engine

The CMP substitutes four tokens with `sed`:

| Token | Set by the ApplicationSet to |
|---|---|
| `${POLICY_NAMESPACE}` | `open-cluster-management-policies` |
| `${REMEDIATION}` | `inform` |
| `${EVAL_COMPLIANT}` | `10m` |
| `${EVAL_NONCOMPLIANT}` | `30s` |

`sed` rather than a template engine is a deliberate constraint, and the reason
is the same collision as above: a template engine would try to evaluate
`{{hub ... hub}}`. Plain string replacement leaves hub templates untouched to
be resolved on the hub, where they belong.

### Per-cluster values

`policy-values/` holds flat `KEY=value` files — `global.env` for the fleet and
`clusters/<managed-cluster-name>.env` per cluster. `cluster-config-maps` turns
them into ConfigMaps in the policy namespace, which hub templates then read:

```yaml
'{{hub dig "data" "etcdEncryptionType" ""
  (lookup "v1" "ConfigMap" "open-cluster-management-policies"
    (printf "policy-config-%s" .ManagedClusterName))
  | default (fromConfigMap "open-cluster-management-policies" "policy-config" "etcdEncryptionType") hub}}'
```

Two tiers: the cluster's own ConfigMap wins, the fleet default fills in. The
per-cluster half uses `lookup` rather than `fromConfigMap` because `lookup`
returns an empty result for a cluster that has no ConfigMap, while
`fromConfigMap` raises and takes the whole policy down. `fromConfigMap` is
correct for the second half precisely because that ConfigMap is always
present, so an error there is a real error.

Note that `clusters/<name>.env` must be named for the **ManagedCluster** name,
not the cluster's friendly name — hence `local-cluster.env`, not `acm-hub.env`.

### ACM's template engine is not Helm's

Worth knowing before writing a hub template, because the failure arrives at
propagation time rather than at render time:

**There is no `fromYaml`, `toYaml`, `trimSuffix`, `trimPrefix` or `toJson`.**
ACM's engine (`stolostron/go-template-utils`) exposes a *subset* of sprig —
v6 by explicit allowlist, v7 by denylist over `sprig.FuncMap()` — and the YAML
helpers are Helm additions that sprig itself never had. They are absent in
both.

Available and used here: `dig`, `get`, `merge`, `default`, `replace`,
`fromJson`, `toRawJson`, plus ACM's own `fromConfigMap`, `lookup`, `indent`,
`toLiteral`, `toInt`, `toBool`.

This is why `policy-values/` holds flat `.env` files rather than structured
YAML. An earlier draft parsed nested YAML out of a ConfigMap with `fromYaml`
and would have failed on every cluster. Flattening moves the merge into
kustomize, where a real YAML parser exists.

`toLiteral` is how a list survives the trip: a ConfigMap holds only strings,
so `allowedRegistries` is stored as a JSON array and `toLiteral` strips the
quotes so it lands as a YAML sequence rather than a string that looks like one.

### Why not reuse the existing per-cluster values files

Every other configurable thing in this repo reads `env/<env>/*.yaml` then
`clusters/<env>/<cluster>/*.yaml`, with Helm doing the merge. `policy-values/`
is a second, parallel values tree, which is a cost worth justifying. Three
independent reasons, any one of them sufficient:

1. **There is no Helm on the policy path.** The existing files are consumed by
   `valueFiles` lists in the cluster ApplicationSets. `hub-acm-policies` renders
   through a ConfigManagementPlugin whose only inputs are the four `${TOKEN}`
   env vars. There is nowhere to hand a values file to.
2. **No `fromYaml`** — see the section above. Even if `platform-config.yaml`
   reached the hub intact inside a ConfigMap key, a hub template could not parse
   it at propagation time. Values have to arrive already flat.
3. **Different key space.** Cluster values key on the directory name,
   policy values on the ManagedCluster name; for the hub those are `acm-hub` and
   `local-cluster`. And the `clusters/**/conf.yaml` generators run
   `goTemplateOptions: [missingkey=error]`, so a new `policies:` key there would
   have to be added to every cluster directory at once or every ApplicationSet
   breaks.

**If the duplication ever becomes real, here is the escape hatch.** The policies
hardcode only the ConfigMap *names* — `policy-config` and
`policy-config-<ManagedClusterName>` — not any filesystem path.
`cluster-config-maps` is simply the current writer of those two objects, not a
required one. A Helm chart could read nested per-cluster YAML, flatten it (Helm
*does* have `fromYaml`/`toYaml`), and write the same ConfigMaps, delivered by an
ApplicationSet whose destination is pinned to the hub —
`clusters/mgt/acm-hub/applicationsets/cluster-import.yaml` already does exactly
that pinning. The merge would then come free from the `env/` → `clusters/`
chain, and `policy-values/` could go away.

The reason that is not built: `global.env` holds two keys and
`clusters/local-cluster.env` holds none. A merge mechanism with nothing to merge
is machinery to maintain for no benefit. Revisit when several managed clusters
genuinely diverge.

### API notes

**`PlacementRule` is deprecated.** The CRD is still served on 2.17, but it is
the superseded API. This repo uses `Placement` + `ManagedClusterSetBinding`
throughout.

**Compliance Operator is an `OperatorPolicy`.**
`policy.open-cluster-management.io/v1beta1 OperatorPolicy` is purpose-built
for operator lifecycle — channel, version, install-plan approval, upgrade
state. A ConfigurationPolicy wrapping a Subscription understands none of
that: it can tell you a Subscription object exists, not that the operator is
healthy or current. PolicyGenerator passes `policy.open-cluster-management.io`
kinds through un-wrapped, so an `OperatorPolicy` in `manifests/` becomes a
policy template directly.

**No `preserveResourcesOnDeletion`.** For policies it would mean that deleting
a directory leaves the Policy live on the hub — a governance control that
outlives its own definition.

### Authoring a policy

```bash
scripts/generate-policy.sh my-check              # or --operator for an OperatorPolicy
$EDITOR policies/stable/my-check/manifests/
make validate-policies
```

`make install-policy-generator` fetches pinned `kustomize` and
`PolicyGenerator` into `.tools/` first. See `policies/README.md` for the
walkthrough.

## Alerting

An inform-only model is worth exactly as much as its notification path. A
policy that reports non-compliant to a dashboard nobody opens has not
detected drift — it has recorded it.

The path needs no new operator and no observability stack — the metric source
and the scrape are already running. It does need two existing charts turned on
for the hub, which is a bigger lift than it sounds; see the prerequisite below.

```
grc-policy-propagator  ──emits──>  policy_governance_info
  └─ ServiceMonitor (ocm-grc-policy-propagator-metrics)
     └─ platform Prometheus (prometheus-k8s, openshift-monitoring)
        └─ PrometheusRule   <── prometheus-rules chart
           └─ Alertmanager  <── alertmanager-config chart
```

Four things make this work today, all verified on the hub:

- `open-cluster-management` is labelled `openshift.io/cluster-monitoring: "true"`,
  so **platform** Prometheus scrapes it — not user-workload monitoring. The
  distinction decides which namespace the `PrometheusRule` has to live in.
- The propagator's ServiceMonitor target is active, and its
  `ocm_handle_root_policy_duration_seconds` series are already in
  `prometheus-k8s`. The scrape path is proven, independent of any policy
  existing.
- `prometheus-rules` writes its `PrometheusRule` to `openshift-monitoring`,
  which is where platform Prometheus evaluates rules. The chart's existing
  shape — a per-domain `include` toggle plus thresholds — takes a `governance`
  block with no structural change.
- The propagator runs on the **hub** and emits compliance for every managed
  cluster, so hub-local Prometheus sees the whole fleet.

That last point matters: there is **no `MultiClusterObservability`** on this
hub. The `advanced-cluster-management` chart carries observability templates,
but no MCO instance exists, so the Thanos aggregation path is not available.
Governance alerting does not need it.

### The three alerts

**1. Drift.** A policy reports non-compliant on some cluster. This is the
drift alarm the whole inform-only model exists to produce — a cluster has
diverged from git.

**2. Inert policy.** The failure mode from the placement section, instrumented.
A policy that selects no clusters produces *no propagated series at all*,
which is invisible to alert (1) — there is nothing to compare against a
threshold. The alert is structural: a root policy exists, and no propagated
instances of it do.

```promql
count by (policy_namespace, policy) (policy_governance_info{type="root"})
  unless
count by (policy_namespace, policy) (policy_governance_info{type="propagated"})
```

This is the alert that stops a governance control from being believed when
it is doing nothing. It should be treated as at least as serious as a
compliance failure, because it is a failure of the detector rather than of
the thing detected.

**3. Reporting gone silent.** A cluster stops reporting compliance — the
policy framework addon is down, or the cluster is unreachable. Absence of a
signal is not compliance, and alerts (1) and (2) both go quiet in this case.

> **To confirm before implementing:** the exact label set on
> `policy_governance_info` (`type`, `policy`, `policy_namespace`,
> `cluster_namespace`) and its value convention (0 compliant / 1 non-compliant)
> are from the ACM documentation, not from this hub — the metric has no series
> yet because no policies exist. The expression above is therefore a shape, not
> a tested query. Verify against real series as soon as the first policy is
> placed, before writing the rule.

### Prerequisite: the hub runs neither alerting chart

The rule has to live on the **hub**, because that is where the propagator
emits. But `clusters/mgt/acm-hub/conf.yaml` lists neither `prometheus-rules`
nor `alertmanager-config` — both are enabled on `example-cluster`, a managed
cluster, and nowhere else. `user-workload-monitoring` is commented out on the
hub as well.

So governance alerting is not just "add a rule". It requires enabling
`prometheus-rules` and `alertmanager-config` on the hub first. That is a
larger change than the policy work itself, and it lands on the cluster
running the management plane, so it deserves its own change rather than
riding along with a policy chart.

The ordering that follows: policies can be written, placed and observed on
the ACM console without any of this. Alerting is a second phase with its own
prerequisite, not part of the first policy landing.

### Severity

Policies already carry `severity` (low → critical); Alertmanager routes on a
`severity` label of its own (info / warning / critical). The mapping between
them is a decision, not a given, and the honest default is conservative:
nothing routes to a pager until someone has watched the alert behave for a
while. Start everything at `warning`, promote individually once a policy has
proven it does not flap.

## Open questions

- **Cluster set topology.** Everything is in `default` today because that is
  the only set that exists. `production`/`nonprod`/`mgmt` is the obvious cut,
  but with a one-cluster fleet there is no evidence for it yet, and creating
  sets before there are clusters to put in them risks guessing wrong. When
  sets do appear, `policy-framework` gains a binding per set and the policies
  that should be narrower gain a `clusterSets` field in their placement.
- **Where `local-cluster` lands.** Its own set (`mgmt`), or in with everything
  else? It is the only cluster that is both governed and governing.
- **The `certified/` and `community/` tiers are empty.** The ApplicationSet
  globs `policies/*/*/kustomization.yaml`, so they work the moment something
  is put in them, and the Application carries a `tier` label. What belongs in
  each — vendor-supplied policies, Red Hat's policy-collection, local
  experiments — has not been decided.
- **Where alerts actually go.** `alertmanager-config` is enabled on `example-cluster`
  with `include: true` and no receiver — Slack, PagerDuty, email and webhook
  are all empty stubs, and there is no live `AlertmanagerConfig` on the hub.
  The rule can be written before a receiver is chosen; it just fires into
  nothing until one is.
- **Relationship to Compliance Operator and ACS.** Three systems that all
  report compliance. ACM Policy attests to configuration, Compliance Operator
  scans against CIS/STIG benchmarks, ACS covers runtime and image policy.
  The overlap is real and currently unmapped.
- **Gatekeeper / Kyverno.** Both are available as operator charts and neither
  is enabled on any cluster. Admission control is a different mechanism from
  periodic attestation — it refuses rather than reports. If one is ever turned
  on, this ownership table needs a fourth column.

## See also

- [`policies/README.md`](../../policies/README.md) — authoring walkthrough
- [`policy-values/README.md`](../../policy-values/README.md) — per-cluster values
- [Day 2 Cluster Configuration](../day2-cluster-config/README.md) — the charts
  on the writing half of the ownership contract
- [Compliance Operator setup](../day2-cluster-config/compliance.md) — benchmark
  scanning, distinct from policy attestation
- [ApplicationSets](../cluster-configuration/applicationsets.md) — how charts
  reach managed clusters, i.e. the writing half of the contract above
