# Chart Categories

All Helm charts are organized by category under `charts/`. Each category corresponds to an ApplicationSet that manages deployment.

## Platform config (`charts/platform-config/`)

Day-2 platform configuration charts. Each chart manages a specific OpenShift subsystem — TLS, OAuth, API server settings, ingress, monitoring, RBAC, etc. Driven by the `platformCharts` list in `conf.yaml` and configured via `platform-config.yaml`.

Charts: `acm-managed-cluster`, `acm-policies`, `admin-network-policy`, `alertmanager-config`, `etcd-backup`, `etcd-defrag`, `global-pull-secrets`, `image-mirror-config`, `image-pruner`, `machine-health-checks`, `openshift-apiserver`, `openshift-build`, `openshift-console`, `openshift-dns`, `openshift-group-sync`, `openshift-image`, `openshift-image-registry`, `openshift-ingress`, `openshift-machine-config`, `openshift-marketplace`, `openshift-oauth`, `openshift-proxy`, `openshift-scheduler`, `project-request-template`, `prometheus-rules`, `pure-storage-node-config`, `rbac`, `storage-classes`, `tls-certificates`, `user-workload-monitoring`, `vault-server`, `volume-snapshot-classes`.

## Operator instances (`charts/operator-instances/`)

Charts that deploy Custom Resources for operators — the operator's actual workload configuration, not the operator subscription itself. Driven by the `operatorInstanceCharts` list in `conf.yaml` and configured via `operator-instances.yaml`.

Charts: `aap-instance`, `acm-multiclusterhub`, `acm-observability`, `acs-central`, `acs-secured-cluster`, `cert-manager-certs`, `compliance-scans`, `external-secrets`, `gatekeeper-instance`, `group-sync`, `keycloak-instance`, `kyverno-instance`, `local-storage-volumes`, `logging-lokistack`, `lvm-cluster`, `metallb-config`, `mtv-controller`, `nmstate-config`, `node-feature-discovery-instance`, `oadp-config`, `odf-storagecluster`, `openshift-gitops-instance`, `openshift-virtualization-instance`, `opentelemetry-instance`, `quay-registry`, `servicemesh-ambient`, `servicemesh3-instance`, `tempo-instance`, `trident-config`, `trusted-artifact-signer-instance`, `velero-config`.

## Operator deployment (`charts/operator-deployment/`)

A single chart that manages all operator Subscriptions via OLM. Controlled by `deployOperators: true` in `conf.yaml` and configured via `operator-deployment.yaml`. Each operator is gated by its own `include: false` default — enable only what the cluster needs.

## Onboarding (`charts/onboarding/`)

Team onboarding charts. The `teams` list in `conf.yaml` drives these — each team gets:

- **application-gitops** — an ArgoCD AppProject scoped to the team's namespaces
- **namespace-config** — namespaces with ResourceQuotas, LimitRanges, and NetworkPolicies

## Cluster provisioning (`charts/cluster-provisioning/`)

Covered in the [Cluster Provisioning](../cluster-provisioning/) guide.
