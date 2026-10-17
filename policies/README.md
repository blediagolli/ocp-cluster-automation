# ACM Policies

Fleet governance for the ACM hub. Each directory under `stable/`, `certified/`
or `community/` is one policy, rendered by
[PolicyGenerator](https://github.com/open-cluster-management-io/policy-generator-plugin)
and delivered by the `hub-acm-policies` ApplicationSet.

**Policies attest; charts configure.** Everything here runs
`remediationAction: inform` with one documented exception. A policy's job is
to answer "does the fleet hold this property?", never to make it true — the
`platform-config` charts make it true. A failing policy is a drift alarm, not
a repair job. The reasoning, and the one exception, are in
[docs/governance/acm-policies.md](../docs/governance/acm-policies.md).

## Layout

```
policies/
  stable/          in production use
  certified/       (empty) vendor-supplied
  community/       (empty) experimental
```

The tier is just the first path segment; the ApplicationSet globs
`policies/*/*/kustomization.yaml` and copies the tier onto each Application as
a `tier` label. Adding a directory to any tier is all it takes to deploy it,
unless it opts out — see [Authoring without deploying](#authoring-without-deploying).

This tree is at the repo root rather than under `clusters/mgt/acm-hub/`, even
though the hub is the only cluster that hosts it — a `clusters/<env>/<name>/`
directory is configuration applied *to* that cluster, and a policy is fleet
governance the hub merely delivers. Reasoning and the concrete cost of moving
it: [Why the tree sits at the repo root](../docs/governance/acm-policies.md#why-the-tree-sits-at-the-repo-root).

Three directories under `stable/` are infrastructure rather than controls:

| Directory | Role |
|---|---|
| `policy-framework` | Namespace, `ManagedClusterSetBinding`, and the `security-baseline` PolicySet. Plain kustomize, no PolicyGenerator — it creates the things a Policy needs in order to exist |
| `cluster-config-maps` | Turns `policy-values/` into ConfigMaps that hub templates read |
| `cluster-labels` | The one enforcing policy: stamps `oca.io/*` labels onto `ManagedCluster` objects, which no chart can write |

## Adding a policy

```bash
make install-policy-generator          # once: pinned kustomize + plugin into .tools/
scripts/generate-policy.sh my-check    # add --operator for an OperatorPolicy
```

That scaffolds:

```
policies/stable/my-check/
  kustomization.yaml            marker file the ApplicationSet globs for
  policy-generator-config.yaml  what to wrap and with what metadata
  placement.yaml                who it applies to
  manifests/                    the plain Kubernetes YAML being attested
  README.md
```

Write the object you want to attest into `manifests/` as ordinary Kubernetes
YAML — no Policy wrapper, no Helm. Then:

```bash
make validate-policies
```

which reproduces exactly what the repo-server's plugin does: substitute the
four `${TOKEN}`s, then `kustomize build --enable-alpha-plugins`. Run it before
pushing. A plugin failure in ArgoCD surfaces as an opaque `ComparisonError`,
so catching it locally is the difference between a typo and an afternoon.

Useful flags: `--tier`, `--severity`, `--categories`, `--controls`,
`--namespace`, `--channel`. `scripts/generate-operator-policy.sh` is the same
script with `--operator` preset.

The name must be a DNS label of 56 characters or fewer — the Policy is named
`policy-<name>` and 63 is the hard limit.

## Authoring without deploying

To keep a policy in the repo without delivering it, annotate its
`kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  annotations:
    oca.io/deploy: "false"
generators:
  - policy-generator-config.yaml
```

The `hub-acm-policies` ApplicationSet selects on that annotation and filters
the parameters out *before* building anything, so the policy produces **no
Application at all** — not an empty one, and not a Policy with
`spec.disabled`. Remove the annotation to deploy it.

`make validate-policies` globs the directories itself and never reads the
annotation, so a gated policy is still rendered and still fails the build if
it is malformed. Authoring it un-deployed does not mean authoring it
unchecked.

The default is on. A policy with no annotation is deployed, so a control is
never silently withheld by omission — only by an explicit `"false"` that shows
up in review.

It has to be this annotation in this file. The ApplicationSet reads the
*contents* of the file it globs, so the flag must live in `kustomization.yaml`,
and `metadata.annotations` is the only legal place inside it — kustomize
rejects an unknown top-level field outright. It is dropped from the rendered
output, so it never reaches the Policy.

> **Gating a live policy deletes it.** The ApplicationSet has no
> `preserveResourcesOnDeletion`, by design: a control that outlives its own
> definition is worse than no control. Annotating an established policy
> therefore removes its Application *and* its Policy from the hub. This is an
> authoring state, not a pause button. Never gate `policy-framework` — it owns
> the namespace, `ManagedClusterSetBinding` and PolicySet that every other
> policy depends on.

## House rules

**`inform`, unless you can show no chart reaches the object.** Not "enforcing
is more convenient" — a demonstration. An enforcing policy on an object ArgoCD
also writes gives you two controllers with independent reconcile loops and no
shared desired state, and the object flaps while both report success.

**If a manifest duplicates something a chart writes, say so.** Several
`manifests/` files carry a `# Written by: <chart>` header naming their source.
`musthave` compares the fields it names, so a drift between the two files
produces a *false* non-compliance rather than a caught one. Change the chart,
change the policy.

**Do not narrow a placement without a reason.** The scaffolded placement has
no label predicates: any cluster in a bound ManagedClusterSet is in scope. A
placement that matches zero clusters reports **Compliant** — indistinguishable
on the dashboard from one that genuinely passes everywhere. A governance
control that is silently inert is worse than no control, because it is
believed.

**Cluster-scoped singletons get no `namespaceSelector`.** `APIServer/cluster`
and `Image/cluster` are not namespaced; a selector there narrows nothing and
only implies the object is something it isn't.

## Hub templates

Per-cluster values come from `policy-values/` via `{{hub ... hub}}` templates.
Before writing one, read the "ACM's template engine is not Helm's" section of
[the governance doc](../docs/governance/acm-policies.md#acms-template-engine-is-not-helms):
**there is no `fromYaml`, `toYaml`, `trimSuffix`, `trimPrefix` or `toJson`**.
ACM exposes a subset of sprig, and the YAML helpers are Helm additions. A
template using them renders fine locally and fails at propagation time.

## Verifying on the hub

```bash
oc get applications -n openshift-gitops -l type=acm-policy
oc get placement,placementbinding,policy,policyset -n open-cluster-management-policies
oc get managedclustersetbinding -n open-cluster-management-policies

# the one that matters -- a policy with no placement decisions is not passing
oc get policy -A | grep local-cluster
```

An empty second result with a Compliant first result is the silent-inert
failure, not a success.
