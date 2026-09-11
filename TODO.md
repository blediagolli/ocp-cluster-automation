# End-to-End Testing Status

**Generated:** 2026-09-11

## Legend
- **Tested** — deployed on a live cluster, synced, and verified working
- **Synced** — ArgoCD shows Synced/Healthy but functionality not verified end-to-end
- **Not deployed** — chart exists but is not in any cluster's chart list

## Active Charts (deployed on at least one cluster)

| Chart                          | Hub | Dev | Prod | E2E     | Notes                                                          |
|--------------------------------|-----|-----|------|---------|----------------------------------------------------------------|
| operator-deployment            | Yes | Yes | Yes  | Tested  | 9 operators on hub, 2 on dev/prod                              |
| openshift-gitops-instance      | Yes | —   | —    | Tested  | ArgoCD CR, AppProject, RBAC                                    |
| acm-multiclusterhub            | Yes | —   | —    | Tested  | MCH, hive, gitops-cluster, assisted-service                    |
| acs-central                    | Yes | —   | —    | Tested  | Central + init-bundle + credential distribution                |
| acs-secured-cluster            | Yes | Yes | Yes  | Partial | Hub+dev tested; prod generate mode not verified                |
| aap-instance                   | Yes | Yes | Yes  | No      | Synced but AAP functionality not verified                      |
| acm-observability              | Yes | —   | —    | Partial | Pods running; metrics flow from managed clusters not verified  |
| quay-registry                  | Yes | —   | —    | Tested  | Full e2e: bridge, build, push, pull, cleanup                   |
| acm-managed-cluster            | —   | Yes | Yes  | Tested  | Import, addons, GitOpsCluster auto-registration                |
| user-workload-monitoring       | Yes | Yes | Yes  | Partial | Hub tested with persistent storage; dev/prod using defaults    |
| etcd-backup                    | Yes | —   | —    | Partial | OBC mode configured; last backup job not confirmed             |
| etcd-defrag                    | Yes | —   | —    | Tested  | 3 members at 11% frag, correctly skipped                       |
| project-request-template       | Yes | —   | —    | Partial | Synced; project creation with template not tested              |
| openshift-marketplace          | —   | Yes | Yes  | No      | Synced but catalog sources not verified                        |
| onboarding: application-gitops | —   | Yes | —    | Tested  | team-alpha + team-beta, ArgoCD instances running               |
| onboarding: namespace-config   | —   | Yes | —    | Tested  | Environment-scoped namespaces, auto-prune verified             |

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

| #   | Test                                       | Why                                                             |
|-----|--------------------------------------------|-----------------------------------------------------------------|
| 1   | ACS SecuredCluster generate mode on prod   | Prod cluster imported but TLS secret generation not verified    |
| 2   | ACM Observability metrics flow             | Thanos stack running but no confirmation metrics arrive         |
| 3   | etcd-backup Job completion                 | OBC mode configured but last backup job status unknown          |
| 4   | Team onboarding on prod                    | Tested on dev only — verify prod namespaces get the right sizes |
| 5   | AAP instance functionality                 | Synced on 3 clusters but AAP not verified working               |
| 6   | project-request-template                   | Synced on hub but new project creation not tested               |
| 7   | NetworkPolicy in namespace-config          | Outstanding — no template exists yet                            |
