# ApplicationSet Mechanics

How the eight ApplicationSets discover clusters and generate ArgoCD Applications.

## Matrix generator with elementsYaml

The `cluster-platform-config` and `cluster-operator-instances` ApplicationSets use a matrix generator that crosses the git file generator (discovers clusters) with a dynamic list from the cluster's `conf.yaml`.

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
            elementsYaml: "{{ .platformCharts | toJson }}"
```

For a cluster with `platformCharts: [{chart: tls-certificates}, {chart: openshift-ingress}]`, this generates two ArgoCD Applications:
- `platform-dev-my-cluster-tls-certificates`
- `platform-dev-my-cluster-openshift-ingress`

### How it works

1. The **git file generator** scans `clusters/**/conf.yaml` and extracts each file's contents as template variables
2. The **list generator** uses `elementsYaml` to parse the `platformCharts` (or `operatorInstanceCharts`) array from each `conf.yaml`
3. The **matrix** crosses every cluster with every chart in its list, producing one Application per combination

Adding a chart to the list creates a new Application; removing it deletes the Application (but preserves resources due to `preserveResourcesOnDeletion`).

## Boolean gates with conditional lists

The provisioning, import, overlay, and operators ApplicationSets use a conditional pattern to gate on a boolean:

```yaml
elementsYaml: "{{ if .deployProvision }}[{}]{{ else }}[]{{ end }}"
```

If `deployProvision: false` (or absent), the list is empty and no Application is generated. If `true`, the list contains a single empty element, and the matrix produces one Application for that cluster.

### Which ApplicationSets use boolean gates

| ApplicationSet | Gate field |
|---|---|
| `cluster-provisioning` | `deployProvision` |
| `cluster-import` | `deployImport` |
| `cluster-config-overlays` | `deployOverlay` |
| `cluster-operators-appset` | `deployOperators` |

## Team-driven generators

The `cluster-onboarding-gitops` and `cluster-onboarding-namespaces` ApplicationSets use the `teams` list in `conf.yaml`:

```yaml
elementsYaml: "{{ .teams | toJson }}"
```

Each team entry generates a separate Application — one ArgoCD AppProject and one namespace set per team per cluster.
