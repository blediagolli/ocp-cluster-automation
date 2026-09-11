# End-to-End Testing Status

**Generated:** 2026-09-11

## Legend
- **Tested** — deployed on a live cluster, synced, and verified working
- **Synced** — ArgoCD shows Synced/Healthy but functionality not verified end-to-end
- **Not deployed** — chart exists but is not in any cluster's chart list

## Active Charts (deployed on at least one cluster)

| Chart                          | Hub | Dev | Prod | E2E     | Notes                                                          |
|--------------------------------|-----|-----|------|---------|----------------------------------------------------------------|
| operator-deployment            | Yes | Yes | Yes  | Tested  | Hub 26/26 operators passed                                     |
| openshift-gitops-instance      | Yes | —   | —    | Tested  | Hub 5/5 — CR, pods, route, AppProject, CRB                    |
| acm-multiclusterhub            | Yes | —   | —    | Tested  | Hub 6/6 — MCH, components, assisted, hive, GitOpsCluster      |
| acs-central                    | Yes | —   | —    | Tested  | Hub 5/5 — CR, pods, API /v1/ping, init-bundle, scanner        |
| acs-secured-cluster            | Yes | Yes | Yes  | Tested  | Hub 5/5, dev 5/5; prod not yet tested                         |
| aap-instance                   | Yes | Yes | Yes  | Failing | Hub 2/5, dev 2/5 — AAP controller not deploying               |
| acm-observability              | Yes | —   | —    | Tested  | Hub 6/6 — Thanos, OBC, Grafana, addon on managed clusters     |
| quay-registry                  | Yes | —   | —    | Tested  | Full e2e: bridge, build, push, pull, cleanup                   |
| acm-managed-cluster            | —   | Yes | Yes  | Tested  | Hub 5/5 both clusters — joined, available, 9/9 addons, ArgoCD |
| user-workload-monitoring       | Yes | Yes | Yes  | Tested  | Hub 5/5 — Prometheus, Thanos Ruler, metrics query              |
| etcd-backup                    | Yes | —   | —    | Partial | Hub 4/5 — CronJob+RBAC+OBC ok, no completed Job yet           |
| etcd-defrag                    | Yes | —   | —    | Partial | Hub 4/5 — CronJob+RBAC+alerts ok, weekly schedule not fired   |
| project-request-template       | Yes | —   | —    | Tested  | Hub 5/5 — created test project, verified NP/RQ/LR, cleaned up |
| openshift-marketplace          | —   | Yes | Yes  | Partial | Dev 1/4 — local CatalogSources not enabled (using defaults)   |
| onboarding: application-gitops | —   | Yes | —    | Tested  | Dev 5/5 alpha, 5/5 beta — ArgoCD, AppProject, RoleBinding     |
| onboarding: namespace-config   | —   | Yes | —    | Tested  | Dev 8/8 alpha — namespaces, quotas, limits match size tier     |

## Not Yet Deployed Charts

### Operator Instances

| Chart                              | Blocker / Next Step                                    |
|------------------------------------|--------------------------------------------------------|
| compliance-scans                   | Add to a cluster's operatorInstanceCharts list          |
| cert-manager-certs                 | Missing dnsNames/SANs — certs will lack SANs           |
| gatekeeper-instance                | No ConstraintTemplates or Constraints included          |
| kyverno-instance                   | Nirmata-specific API — may not match Red Hat operator   |
| local-storage-volumes              | Hardcoded tolerations need parameterizing               |
| logging-lokistack                  | Needs pre-existing S3 credentials secret                |
| lvm-cluster                        | No deviceSelector or nodeSelector                       |
| metallb-config                     | Needs IP pool and BGP peer configuration                |
| mtv-controller                     | Needs source provider (VMware/RHV)                      |
| nmstate-config                     | No NNCP templates for network config                    |
| node-feature-discovery-instance    | Hardcoded image tag, placeholder kconfig path           |
| oadp-config                        | Needs backup storage credentials                        |
| odf-storagecluster                 | No external storage mode support                        |
| openshift-virtualization-instance  | Many hardcoded values need parameterizing               |
| opentelemetry-instance             | Hardcoded Tempo endpoint, insecure TLS                  |
| servicemesh-ambient                | No Gateway or WaypointProxy resources                   |
| servicemesh3-instance              | Jaeger uses memory storage — not production-ready       |
| tempo-instance                     | Needs external S3 secret and CA bundle                  |
| trident-config                     | No TridentBackendConfig or StorageClass                 |
| trusted-artifact-signer-instance   | Missing Fulcio/Rekor configuration                      |
| velero-config                      | Needs OADP operator and cloud-credentials secret        |

### Platform Config

| Chart                    | Blocker / Next Step                                         |
|--------------------------|-------------------------------------------------------------|
| acm-policies             | New chart — test each policy in inform mode first           |
| admin-network-policy     | No policies defined yet                                     |
| alertmanager-config      | Needs receiver secrets (Slack, PagerDuty)                   |
| global-pull-secrets      | Do not commit real credentials — use SealedSecrets          |
| image-mirror-config      | Replace example mirror URLs with real registry              |
| image-pruner             | Ready to enable — good baseline hygiene                     |
| machine-health-checks    | Ready to enable and test                                    |
| openshift-apiserver-audit| Needs TLS secrets for named certificates                    |
| openshift-build          | Useful for air-gapped/proxied environments                  |
| openshift-console        | Ready to enable with branding/notification values           |
| openshift-dns            | Minimal — missing upstream forwarders                       |
| openshift-group-sync     | Needs LDAP connection details                               |
| openshift-image          | allowedRegistries/blockedRegistries are mutually exclusive   |
| openshift-image-registry | PVC-only — no S3/GCS/Azure support                          |
| openshift-ingress        | Ready to enable for TLS profile configuration               |
| openshift-machine-config | Ready to enable for kubelet/eviction tuning                  |
| openshift-oauth          | Needs identity provider config                              |
| openshift-proxy          | Needs proxy URLs and trusted CA ConfigMap                    |
| openshift-scheduler      | Ready to enable for scheduler profile                       |
| prometheus-rules         | Tune thresholds per environment                             |
| storage-classes          | Replace example provisioners with real infrastructure       |
| volume-snapshot-classes   | Enable with ODF/CSI driver parameters                       |

## Priority E2E Tests

| #   | Test                                       | Status   | Why                                                          |
|-----|--------------------------------------------|----------|--------------------------------------------------------------|
| 1   | ACS SecuredCluster generate mode on prod   | Open     | Prod cluster imported but TLS secret generation not verified |
| 2   | AAP controller deployment                  | Open     | 2/5 on hub+dev — controller pods never start                 |
| 3   | etcd-backup Job completion                 | Waiting  | CronJob exists, OBC bound — waiting for next 6h trigger      |
| 4   | etcd-defrag Job completion                 | Waiting  | CronJob exists — weekly schedule, hasn't fired yet           |
| 5   | Prod cluster e2e tests                     | Open     | All prod charts untested (same set as dev)                   |
| 6   | NetworkPolicy in namespace-config          | Open     | No template exists yet                                       |
| ~~7~~   | ~~ACM Observability metrics flow~~     | **Done** | Hub 6/6 — Thanos + OBC + Grafana + addon verified           |
| ~~8~~   | ~~project-request-template~~           | **Done** | Hub 5/5 — created project, verified NP/RQ/LR injected       |
| ~~9~~   | ~~Team onboarding on dev~~             | **Done** | Dev 5/5+8/8 — ArgoCD + namespaces + quotas verified         |
