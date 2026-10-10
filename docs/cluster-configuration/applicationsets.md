# ApplicationSet Mechanics

How the seven ApplicationSets discover clusters and generate ArgoCD Applications.

## Matrix generator with elementsYaml

The `cluster-platform-config` and `cluster-operators` ApplicationSets use a matrix generator that crosses the git file generator (discovers clusters) with a dynamic list from the cluster's `conf.yaml`.

```yaml
generators:
  - matrix:
      generators:
        - git:
            repoURL: git@github.com:YOUR_ORG/gitops-for-organizations.git
            revision: main
            files:
              - path: "clusters/**/conf.yaml"
        - list:
            elementsYaml: "{{ if .clusterRegistered }}{{ .platformCharts | toJson }}{{ else }}[]{{ end }}"
```

For a cluster with `platformCharts: [{chart: tls-certificates}, {chart: openshift-ingress}]`, this generates two ArgoCD Applications:
- `platform-dev-my-cluster-tls-certificates`
- `platform-dev-my-cluster-openshift-ingress`

### How it works

1. The **git file generator** scans `clusters/**/conf.yaml` and extracts each file's contents as template variables
2. The **list generator** uses `elementsYaml` to parse the `platformCharts` (or `operatorCharts`) array from each `conf.yaml`
3. The **matrix** crosses every cluster with every chart in its list, producing one Application per combination

Adding a chart to the list creates a new Application; removing it deletes the Application (but preserves resources due to `preserveResourcesOnDeletion`).

## Boolean gates with conditional lists

The provisioning, import, overlay, and operators ApplicationSets use a conditional pattern to gate on a boolean:

```yaml
elementsYaml: "{{ if .deployProvision }}[{}]{{ else }}[]{{ end }}"
```

If `deployProvision: false`, the list is empty and no Application is generated. If `true`, the list contains a single empty element, and the matrix produces one Application for that cluster.

The field cannot be absent. Every ApplicationSet sets `goTemplateOptions: [missingkey=error]`, so a lookup for a key the `conf.yaml` does not declare fails the generator outright rather than evaluating as false. That is why every `conf.yaml` carries every gate, set to `false` where unused.

### Which ApplicationSets use boolean gates

| ApplicationSet | Gate field |
|---|---|
| `cluster-provisioning` | `deployProvision` |
| `cluster-import` | `deployImport` |
| `cluster-config-overlays` | `deployOverlay` *and* `clusterRegistered` |

## `clusterRegistered` gates everything that targets the cluster

A cluster can be described in this repo long before it exists. The five ApplicationSets whose Applications land *on the managed cluster* are all gated on `clusterRegistered` as well as their own list or flag:

| ApplicationSet | Generated when |
|---|---|
| `cluster-operators` | `clusterRegistered` and `operatorCharts` is non-empty |
| `cluster-platform-config` | `clusterRegistered` and `platformCharts` is non-empty |
| `onboarding-gitops` | `clusterRegistered` and `teams` is non-empty |
| `onboarding-namespaces` | `clusterRegistered` and `teams` is non-empty |
| `cluster-config-overlays` | `clusterRegistered` and `deployOverlay` |

Without the gate, an unimported cluster still generates Applications, pointing at a destination ArgoCD cannot resolve. That does not fail just the one Application — it fails the whole ApplicationSet, stopping it reconciling for *every* cluster, and surfaces as a Degraded `platform-root`.

`cluster-import` and `cluster-provisioning` are deliberately exempt. They target the hub (`https://kubernetes.default.svc`) and are what bring a managed cluster into existence, so gating them on it already existing would deadlock.

`make validate-clusters` compares the flag against the live hub in both directions. It needs a kubeconfig, so it is not part of plain `make validate`.

## Team-driven generators

The `cluster-onboarding-gitops` and `cluster-onboarding-namespaces` ApplicationSets use the `teams` list in `conf.yaml`:

```yaml
elementsYaml: "{{ if .clusterRegistered }}{{ .teams | toJson }}{{ else }}[]{{ end }}"
```

Each team entry generates a separate Application — one ArgoCD AppProject and one namespace set per team per cluster.
