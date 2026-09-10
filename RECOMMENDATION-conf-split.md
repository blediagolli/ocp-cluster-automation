# Implemented: Collapse redundant ApplicationSet toggles

## Problem

Each `clusters/*/conf.yaml` had redundant toggle fields (`operatorApps`, `importApps`) alongside the actual data blocks (`operators`, `managedCluster`) they controlled.

## What changed

### Removed fields
- `operatorApps` — was `[{}]` (deploy) or `[]` (skip), redundant with `operators` block
- `importApps` — was `[{}]` (deploy) or `[]` (skip), redundant with `managedCluster` block

### Added `deploy` field
A `deploy: true/false` flag added to `operators` and `managedCluster` blocks to control whether the ApplicationSet creates an Application.

`deploy` is intentionally separate from `include`:
- `deploy` — ApplicationSet level: should the ArgoCD Application be created?
- `include` — Helm chart level: should individual resources be rendered within the Application?

`deploy` was chosen over `include` to avoid collision with operator Subscription keys in the Helm chart.

### ApplicationSet generator changes

**cluster-operators-appset.yaml:**
```yaml
# Before
elementsYaml: "{{ .operatorApps | toJson }}"
# After
elementsYaml: "{{ if and .operators .operators.deploy }}[{}]{{ else }}[]{{ end }}"
```

**cluster-import.yaml:**
```yaml
# Before
elementsYaml: "{{ .importApps | toJson }}"
# After
elementsYaml: "{{ if and .managedCluster .managedCluster.deploy }}[{}]{{ else }}[]{{ end }}"
```

### Resulting `clusters/*/conf.yaml` structure

```yaml
cluster:
  name: prod
  environment: prod
  address: "https://kubernetes.default.svc"
configCharts: []
managedCluster:
  deploy: false
  include: true
  name: prod
  ...
operators:
  deploy: false
  openshift-gitops:
    include: false
    channel: gitops-1.21
  ...
```

### Current cluster state

| Cluster | `operators.deploy` | `managedCluster.deploy` | Behavior |
|---|---|---|---|
| dev | `true` | `true` | operators + import apps created |
| prod | `false` | `false` | neither created (not yet deployed) |

### Unchanged
- `configCharts` — kept as a list (generates multiple Applications, not a toggle)
- `conf/<env>/conf.yaml` — no changes needed (pure Helm values, small files)
- `base/` charts — no Helm chart changes
- `cluster-config.yaml` and `cluster-config-overlays.yaml` — unaffected
