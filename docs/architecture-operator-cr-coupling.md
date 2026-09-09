# Architectural Analysis: Coupling Operator Deployment with CR Instantiation

## The Question

Can we combine operator deployment (Subscription/OLM) with the instantiation of that operator's custom resources into a single unit, rather than managing them as separate ArgoCD Applications?

Short answer: **yes, with tradeoffs**. This document covers the approaches, their implications, and how each compares to the current architecture.

---

## Current Architecture

The repo uses a two-tier separation:

```
cluster-operators ApplicationSet          cluster-config ApplicationSet
  └── acm-hub-operators (single App)       ├── config-mgt-acm-hub-acs-central
      ├── Namespace                        ├── config-mgt-acm-hub-quay-registry
      ├── OperatorGroup                    ├── config-mgt-acm-hub-acm-observability
      └── Subscription                     └── ... (one App per chart per cluster)
          (all operators in one chart)          (each chart is independent)
```

**Operators**: All operators are deployed from a single Helm chart (`base/operators/`). One ArgoCD Application per cluster manages every Subscription.

**CRs**: Each operator's configuration is a separate Helm chart under `base/config/<name>/`. Each gets its own ArgoCD Application via the `cluster-config` ApplicationSet.

**The connection is implicit**: CRs depend on CRDs that the operator registers after OLM installs it. There is no formal dependency — ArgoCD retries with backoff if CRDs aren't available yet.

### Current Pain Points

1. **Namespace ownership conflicts** — both the operator chart and config chart can create the same namespace (e.g., `quay-enterprise`), causing ArgoCD shared-resource errors.
2. **CRD race conditions** — config apps may sync before operator CRDs exist, requiring retry loops.
3. **Dual maintenance** — enabling an operator requires changes in two places (`operators.quay.include` + `quayRegistry.include`).
4. **No health gating** — config apps don't wait for the operator to be healthy, only for CRDs to exist.
5. **No ordering guarantee** — both ApplicationSets sync independently.

---

## Approach 1: Merged Chart (Subscription + CRs in One Chart)

### How it works

Combine the operator's Subscription, OperatorGroup, Namespace, and CRs into a single Helm chart. Use sync-waves to order them.

```
base/config/quay-registry/
  templates/
    namespace.yaml          # sync-wave: -3
    operatorgroup.yaml      # sync-wave: -2
    subscription.yaml       # sync-wave: -1
    config-bundle-secret.yaml  # sync-wave: 0
    quayregistry.yaml       # sync-wave: 1
    quay-bridge.yaml        # sync-wave: 2
```

### What you gain

- **Single source of truth** — one `include: true` enables everything.
- **No namespace conflicts** — only one Application owns all resources.
- **Explicit ordering** — sync-waves guarantee Subscription deploys before CRs.
- **Simpler values** — operator channel, CR config, and feature toggles live in one `values.yaml`.
- **Atomic rollback** — reverting the Application reverts both operator and config.

### What breaks

- **Sync-waves don't wait for OLM**. This is the critical gotcha. A sync-wave only guarantees the _resource is applied_ before moving to the next wave. It does NOT wait for:
  - OLM to install the operator from the Subscription
  - The operator to register its CRDs
  - The operator pod to become healthy

  So even with `subscription.yaml` at wave `-1` and `quayregistry.yaml` at wave `1`, the QuayRegistry CR will be applied seconds after the Subscription — long before OLM has installed the operator. ArgoCD will fail with "no matches for kind QuayRegistry" and retry.

  **This is the same race condition you already have, just within one Application instead of across two.** The retry still resolves it, but you've gained nothing in terms of ordering.

- **CRD installation is async and out-of-band**. OLM manages the operator lifecycle independently from ArgoCD. ArgoCD can apply a Subscription, but it cannot know when OLM has finished installing the CSV, created the deployment, and registered the CRDs. No amount of sync-wave configuration fixes this because the CRD registration happens outside the ArgoCD sync process.

- **Operator upgrades become riskier**. If the operator and its CRs are in the same chart, a channel bump (e.g., `stable-3.17` -> `stable-3.18`) and a CR schema change deploy simultaneously. With separation, the operator upgrades first, new CRDs register, then the config chart can be updated. With a merged chart, you're trusting that the new operator version is fully installed before the new CR schema is applied — but sync-waves can't enforce this.

- **Blast radius increases**. A bad CR (e.g., malformed QuayRegistry) can put the entire Application into a degraded state, potentially blocking the Subscription from being updated. With separation, a broken CR doesn't affect the operator's lifecycle.

- **Breaks the shared operators chart**. The current `base/operators/` chart deploys ALL operators in one Application per cluster. If you move Subscriptions into individual config charts, you lose the unified operator inventory. You can no longer see all operators in one place or manage their lifecycle collectively.

### Verdict

Possible but doesn't actually solve the ordering problem. You trade namespace conflicts and dual maintenance for increased blast radius and false confidence in ordering.

---

## Approach 2: ArgoCD Sync Hooks with CRD Wait Jobs

### How it works

Keep the merged chart, but add a Kubernetes Job as a sync hook that waits for the CRD to be available before ArgoCD proceeds to the next wave.

```yaml
# templates/wait-for-crd.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: wait-for-quayregistry-crd
  annotations:
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
    argocd.argoproj.io/sync-wave: "0"
spec:
  template:
    spec:
      containers:
        - name: wait
          image: registry.redhat.io/openshift4/ose-cli:latest
          command:
            - /bin/bash
            - -c
            - |
              until oc get crd quayregistries.quay.redhat.com 2>/dev/null; do
                echo "Waiting for QuayRegistry CRD..."
                sleep 10
              done
      restartPolicy: OnFailure
      serviceAccountName: argocd-application-controller
```

With sync-waves: Subscription at `-1`, wait job at `0`, CRs at `1`.

### What you gain

- **Actual ordering** — the Job blocks ArgoCD from proceeding until the CRD exists.
- **All benefits of Approach 1** — single source of truth, no namespace conflicts.

### What breaks

- **RBAC complexity** — the Job needs permissions to query CRDs cluster-wide. The ArgoCD service account may not have this, and granting it violates least-privilege.
- **Job image management** — you need `ose-cli` or similar available and maintained.
- **Timeout handling** — if OLM fails to install the operator, the Job hangs until the `activeDeadlineSeconds` expires. ArgoCD will show the sync as in-progress for a long time.
- **CRD existence ≠ operator readiness** — the CRD can exist before the operator's controller pod is running. Applying a CR at this point may succeed (the API accepts it) but the operator won't reconcile it until the pod starts. The CR sits unprocessed.
- **One Job per operator** — every merged chart needs its own wait job, each with the right CRD name. Boilerplate accumulates.
- **ArgoCD hook lifecycle** — hooks run on every sync, adding latency to routine operations.

### Verdict

Works but heavy. The engineering cost (RBAC, images, timeouts, maintenance) outweighs the benefit for most deployments.

---

## Approach 3: ArgoCD App-of-Apps with Sync-Waves Between Applications

### How it works

Use the parent Application (`openshift-gitops-config`) to enforce ordering between the operators Application and config Applications via sync-waves at the Application level.

```yaml
# In the parent app-of-apps chart
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: acm-hub-operators
  annotations:
    argocd.argoproj.io/sync-wave: "1"
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: config-mgt-acm-hub-quay-registry
  annotations:
    argocd.argoproj.io/sync-wave: "2"
```

### What you gain

- **Ordering at the Application level** — operators deploy before config.
- **No structural changes** — keep current chart separation.

### What breaks

- **Same CRD race condition**. Sync-waves on Applications work the same way as on resources — they wait for the Application _resource_ to be applied (and optionally healthy), not for OLM to finish installing operators. The operators Application will be "Synced + Healthy" as soon as the Subscriptions are applied, long before CRDs exist.
- **ApplicationSets don't support sync-waves**. The current architecture uses ApplicationSets, which generate Applications. You can template sync-wave annotations, but the ApplicationSet controller doesn't respect them — it generates all Applications at once. You'd need to switch to a manually managed app-of-apps pattern, losing the dynamic generation.
- **Breaks auto-sync model**. If config apps are gated behind operator apps, adding a new config chart requires the parent to sync first. This adds latency and a manual step.

### Verdict

Architecturally clean but doesn't solve the underlying CRD timing problem, and conflicts with the ApplicationSet-driven generation model.

---

## Approach 4: ArgoCD Resource Hooks with Health Checks (Best Hybrid)

### How it works

Keep the current two-tier separation but add custom ArgoCD health checks for Subscriptions that consider the CSV state. ArgoCD already has built-in health checks for many OpenShift resources, but you can add custom Lua health checks.

```lua
-- In argocd-cm ConfigMap or argocd-repo-server config
-- Custom health check for Subscription
hs = {}
if obj.status ~= nil then
  if obj.status.state == "AtLatestKnown" then
    hs.status = "Healthy"
    hs.message = obj.status.currentCSV
  elseif obj.status.state == "UpgradePending" then
    hs.status = "Progressing"
    hs.message = "Upgrade pending"
  else
    hs.status = "Progressing"
    hs.message = obj.status.state or "Waiting for OLM"
  end
end
return hs
```

Combined with the **`argocd.argoproj.io/sync-wave`** annotations on the parent app-of-apps (not ApplicationSets), this gives you real health-gated ordering.

BUT: this still requires moving away from ApplicationSets for the ordering to work, which is the same limitation as Approach 3.

### What you gain

- **Accurate health status** — ArgoCD knows when OLM has actually finished.
- **Better dashboards** — operators show "Progressing" until CSV is installed.

### What breaks

- **Doesn't solve ordering** — health checks improve visibility but don't block config app syncs.
- **Lua maintenance** — custom health checks need updating when OLM status fields change.

### Verdict

Worth doing regardless of the coupling question — better health visibility is always valuable. But it's a visibility improvement, not an ordering solution.

---

## Approach 5: Keep Separation, Fix the Friction (Recommended)

### How it works

Keep the current two-tier separation but address the specific pain points.

#### Fix 1: Eliminate namespace conflicts
Adopt a clear rule: **the operator chart owns namespaces**. Config charts never create namespaces. Remove `namespace.yaml` from config charts entirely (not just `include: false`).

For cases where a config chart needs a namespace that no operator creates (e.g., `open-cluster-management-observability`), add a `namespaces` list to the operators chart that creates non-operator namespaces.

#### Fix 2: Single enable flag
Add a convention where the operator `include` flag also controls the config chart:

```yaml
# conf.yaml — one flag rules both
quay:
  include: true           # Operator + config
  channel: stable-3.17
  registry:               # CR-specific config nested under operator key
    superUsers: [admin]
    bridge:
      include: true
```

The operators chart reads `quay.include` and `quay.channel`. The config chart reads `quay.include` and `quay.registry.*`. One flag to enable, sub-keys for config.

#### Fix 3: Add retry tolerance
ArgoCD already retries. The current retry config (5 retries, backoff to 10 minutes) is sufficient. The CRD race condition resolves itself within 1-3 minutes for most operators. This is a non-problem in practice — it only matters on initial deployment, not on day-2 operations.

#### Fix 4: Document the dependency
Add a comment in each config chart's `Chart.yaml` or `HANDOFF.md` noting which operator it depends on. This is for humans, not machines — the system handles the timing.

### What you gain

- **No namespace conflicts** — clear ownership rule.
- **Simpler enablement** — one flag per operator.
- **No new moving parts** — no Jobs, no Lua, no structural changes.
- **Preserves ApplicationSet model** — dynamic generation continues working.
- **Preserves independent lifecycles** — operator upgrades and config changes are separate operations.

### What you lose

- **Still no formal ordering** — relies on ArgoCD retry. But this is a feature, not a bug: it makes the system eventually consistent without tight coupling.

---

## Comparison Matrix

| Concern | Current | Merged Chart | Sync Hooks | App-of-Apps Waves | Keep Separation (Fixed) |
|---------|---------|-------------|------------|-------------------|------------------------|
| Namespace conflicts | Yes | No | No | Yes | No |
| CRD race condition | Retry | Retry | Solved | Retry | Retry |
| Dual maintenance | Yes | No | No | Yes | No |
| Blast radius | Small | Large | Large | Small | Small |
| Operator upgrade safety | Safe | Risky | Risky | Safe | Safe |
| Works with ApplicationSets | Yes | Yes | Yes | No | Yes |
| Engineering overhead | None | Low | High | Medium | Low |
| Day-2 operational risk | Low | Medium | Medium | Medium | Low |

---

## Recommendation

**Go with Approach 5** — keep the separation, fix the friction. The current architecture's separation of operator lifecycle from operator configuration is a deliberate and valuable design choice. Operators managed by OLM have their own upgrade lifecycle (approval policies, CSV management, CRD versioning) that is fundamentally asynchronous. Trying to force synchronous coupling onto an async system creates complexity without solving the root timing issue.

The real problems — namespace conflicts, dual maintenance flags — are solvable without restructuring. The CRD race condition is already handled by ArgoCD retry and only affects initial cluster bootstrap, not day-2 operations.

If you do want tighter coupling in the future, the cleanest path is Approach 2 (sync hooks with CRD wait jobs) applied selectively to operators that are slow to install CRDs, not as a blanket pattern.

---

## Appendix: Eliminating Empty Applications

A separate but related pain point: the `cluster-config` ApplicationSet generates Applications for every chart in its hardcoded list, even when a chart's `include: false` means it renders nothing. This creates empty Applications that clutter the ArgoCD UI.

### Root cause

The ApplicationSet uses a matrix of `git files × static list`:

```yaml
generators:
  - matrix:
      generators:
        - git:
            files:
              - path: "clusters/**/conf.yaml"
        - list:
            elements:
              - template: quay-registry
              - template: acs-central
              # ...
```

Every cluster gets an Application for every chart in the list — 3 clusters × 7 shared charts × 7 hub charts = many empty apps.

### Solution: `elementsYaml` with dynamic chart lists

ArgoCD 2.7+ (OpenShift GitOps 1.12+) supports `elementsYaml` in the list generator within a matrix. This lets the inner list be dynamic, reading its elements from the outer generator's data.

**Step 1**: Add a `configCharts` list to each cluster's `conf.yaml`:

```yaml
# clusters/mgt/acm-hub/conf.yaml
cluster:
  name: acm-hub
  environment: mgt
  address: "https://kubernetes.default.svc"
configCharts:
  - chart: openshift-machine-config
  - chart: openshift-ingress
  - chart: acs-central
  - chart: quay-registry
  # only list charts this cluster actually deploys
```

**Step 2**: Replace the two matrix generators (shared + hub-only) with one dynamic matrix:

```yaml
generators:
  - matrix:
      generators:
        - git:
            repoURL: git@github.com:blediagolli/gitops-for-organizations.git
            revision: main
            files:
              - path: "clusters/**/conf.yaml"
        - list:
            elementsYaml: "{{ .configCharts | toJson }}"
template:
  metadata:
    name: 'config-{{.cluster.environment}}-{{.cluster.name}}-{{.chart}}'
  spec:
    source:
      path: 'base/config/{{.chart}}'
      helm:
        valueFiles:
          - '/conf/{{.cluster.environment}}/conf.yaml'
          - '/{{.path.path}}/conf.yaml'
    destination:
      server: '{{.cluster.address}}'
```

### What this solves

- **No empty Applications** — only charts listed in `configCharts` generate Applications.
- **No shared vs hub-only split** — each cluster explicitly declares its charts. The two matrix generators collapse into one.
- **Single place to enable** — add/remove a chart from `configCharts` instead of uncommenting lines in the ApplicationSet YAML.
- **Per-cluster control** — dev cluster can have 6 charts, hub can have 12, prod can have 4. No "all clusters get everything" problem.

### What changes

- Each cluster's `conf.yaml` gets a `configCharts` list (additive, no existing keys change).
- The ApplicationSet YAML gets simpler (one generator instead of two).
- The template references `.chart` instead of `.template` for the chart name field.
- Existing chart templates and values are untouched.

### What to watch for

- Removing a chart from `configCharts` will cause the ApplicationSet to delete that Application and its managed resources (if prune is enabled). This is usually the desired behavior but can be surprising.
- The `configCharts` list is the source of truth for what's deployed. The `include` flags in values still control what the chart renders, but the Application itself won't exist unless the chart is in `configCharts`.
