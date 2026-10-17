# Bootstrapping a hub

How a freshly installed cluster goes from bare OpenShift to reconciling this
repo. Four imperative steps, in order, and then nothing imperative ever again.

## The rule

**The app-of-apps is deployed first. The ApplicationSets are never applied by
hand — `platform-root` creates them.**

`clusters/<env>/<cluster>/applications/app-argocd.yaml` defines a single
Application, `platform-root`, whose source path is the cluster directory
itself. That directory's `kustomization.yaml` lists `applications` and
`applicationsets`, so once `platform-root` exists it applies two things: the
eight ApplicationSets, and its own definition. It is self-managing from the
first sync onward.

That makes `platform-root` the one and only entry point. Everything else in the
cluster's GitOps tree descends from it.

## Order

```bash
# 1. The GitOps operator. Its own directory, on its own, first.
oc apply -k clusters/mgt/acm-hub/bootstrap/openshift-gitops/operator

# 2. Wait for the CSV. Do not skip this.
oc get csv -n openshift-gitops-operator -w

# 3. The ArgoCD instance, the platform AppProject, and the CMP sidecar.
oc apply -k clusters/mgt/acm-hub/bootstrap/openshift-gitops/instance
oc apply -k clusters/mgt/acm-hub/bootstrap/openshift-gitops/console-plugin

# 4. The app-of-apps. This is the last thing applied by hand, ever.
oc apply -k clusters/mgt/acm-hub/applications
```

Then stop. `platform-root` syncs, creates the eight ApplicationSets, and from
that point every change reaches the cluster by merging to `main`.

### Why steps 1–3 are not one apply

`oc apply -k clusters/mgt/acm-hub/bootstrap` renders the operator and the
`ArgoCD` CR into one stream. The sync waves on those manifests are an **ArgoCD**
feature — `kubectl`/`oc` ignore them entirely and apply in kustomize's order, so
the `ArgoCD` CR hits the API server before the operator has installed its CRD
and the apply fails. The three-step split is what orders it.

### Why step 4 is not `oc apply -k clusters/mgt/acm-hub`

Applying the whole cluster directory does produce a working cluster —
`platform-root` adopts the ApplicationSets on its first sync, because the names
match. But it teaches the wrong habit, and the habit is what causes the real
failure below. Apply `applications/` only, and let the app-of-apps do its job.

## What goes wrong when ApplicationSets are applied directly

Observed on the acm-hub rebuild, 2026-10-13. The ApplicationSets were applied
with `oc apply -k .../applicationsets` during bootstrap and `platform-root` was
never created. The cluster *looked* fine: eight ApplicationSets present,
generating correctly.

```console
$ oc get applications -n openshift-gitops
No resources found in openshift-gitops namespace.

$ oc get applicationsets -n openshift-gitops \
    -o custom-columns='NAME:.metadata.name,TRACKING:.metadata.annotations.argocd\.argoproj\.io/tracking-id'
NAME                      TRACKING
cluster-config-overlays   <none>
cluster-import            <none>
...
```

No owner, no `argocd.argoproj.io/tracking-id`. Four consequences:

- **Edits in git never reach the cluster.** Nothing syncs these objects, so a
  change to an ApplicationSet sits in `main` with no effect. This is the one
  that actually bites: it presents as "my ApplicationSet change did nothing",
  and the only way to land a fix is another manual `oc apply` — which deepens
  the hole.
- **No drift correction.** `selfHeal` cannot heal an object no Application
  claims. An edit made directly against the cluster is permanent.
- **No single source of truth for what the hub runs.** `oc get applications`
  returns nothing, so the inventory lives only in someone's memory.
- **Removal does not propagate.** Deleting an ApplicationSet from
  `applicationsets/kustomization.yaml` leaves the live object running.

### Recovery

Apply the app-of-apps. ArgoCD adopts same-named objects, so nothing is deleted
or recreated:

```bash
oc apply -k clusters/mgt/acm-hub/applications
```

Confirm adoption — every ApplicationSet should now carry a tracking-id naming
`platform-root`:

```bash
oc get applicationsets -n openshift-gitops \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.argocd\.argoproj\.io/tracking-id}{"\n"}{end}'
```

`platform-root` sets `selfHeal: true` without `prune`, so adoption cannot
delete anything that happens not to be in git.

## Bringing charts back after a rebuild

A rebuilt hub should come up bare: `platformCharts`, `operatorCharts` and
`teams` all `[]`, and `deployPolicies: false`. The ApplicationSets then exist
and generate nothing, which is the point — the first sync is a no-op rather
than the whole platform landing at once on a cluster nobody has looked at.

Charts go back **one at a time, each verified before the next**, by adding a
name to a list in `conf.yaml` and merging. Suggested order, and why:

| Order | Chart | Why here |
|---|---|---|
| 1 | `cert-manager` | Issues the certificates other charts name |
| 2 | `external-secrets`, `vault-server` | Secrets other charts reference |
| 3 | `tls-certificates`, then its consumers | Ingress and the API server |
| 4 | `odf` | Heaviest; size it before anything competes with it |
| 5 | `advanced-cluster-management` | What makes this a hub at all; its observability needs ODF |
| 6 | `deployPolicies` | Optional; needs the CRDs the MultiClusterHub installs |
| 7 | everything else | |

ODF goes **before** ACM. It is the only component big enough to not fit, and an
otherwise-light cluster is the only place that shows up cleanly — on the first
hub it was ODF's requests that left DaemonSet pods permanently `Pending`, and a
DaemonSet pod cannot be rescued by adding nodes.

`deployPolicies` is optional and last. It turns on only after ACM's
**MultiClusterHub is Running** — not when its Subscription reaches
`AtLatestKnown`; the policy framework CRDs arrive with the MCH, not the CSV. And
it changes what you can see rather than what the cluster does: every policy
renders with `REMEDIATION=inform`.

That table is the summary. The sequence as actually run — the dependency fixing
each position, what to verify between merges, and the hazard on each chart's
first sync — is in the [cluster buildout runbook](../cluster-buildout.md#stage-4--the-order),
which also covers the stages either side of this page.

## Related

- [Cluster buildout runbook](../cluster-buildout.md) — this page is its Stage 2

- [ApplicationSet mechanics](applicationsets.md) — generators, gates, `elementsYaml`
- [conf.yaml](conf-yaml.md) — the per-cluster switches the generators read
- [Chart readiness](chart-readiness.md) — which charts have actually run
