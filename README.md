# GitOps for Organizations

A production GitOps framework for provisioning and configuring OpenShift clusters at scale using Red Hat Advanced Cluster Management (ACM), OpenShift GitOps (ArgoCD), and Helm. Git is the source of truth — every cluster, operator, and platform configuration change flows through a git commit.

## Repository layout

```
clusters/                      Per-cluster configuration
  mgt/acm-hub/                 Hub cluster (ApplicationSets, bootstrap, policies)
  dev/aws-test/                Development cluster
  prod/                        Production clusters
env/                           Environment-level defaults (dev/, mgt/, prod/)
charts/                        Helm charts
  platform-config/             31 day-2 platform charts (TLS, OAuth, etcd, ingress, ...)
  operator-instances/          31 operator CR charts (ACS, Keycloak, Quay, cert-manager, ...)
  operator-deployment/         Single chart — all operator Subscriptions via OLM
  onboarding/                  Team onboarding (ArgoCD projects, namespace provisioning)
  cluster-provisioning/        Cluster provisioning (ACM/Hive, sushy-ec2 emulator)
teams/                         Team definitions
docs/                          Documentation
scripts/                       Utility scripts
```

## How it works

Eight ApplicationSets on the hub cluster drive everything:

| ApplicationSet | What it does | Trigger |
|---|---|---|
| `cluster-platform-config` | Deploys platform-config charts per cluster | `platformCharts` list in conf.yaml |
| `cluster-operator-instances` | Deploys operator CR charts per cluster | `operatorInstanceCharts` list in conf.yaml |
| `cluster-operators-appset` | Deploys operator Subscriptions per cluster | `deployOperators: true` |
| `cluster-config-overlays` | Deploys cluster-specific overlays | `deployOverlay: true` |
| `cluster-import` | Imports clusters into ACM | `deployImport: true` |
| `cluster-provisioning` | Provisions clusters via ACM/Hive | `deployProvision: true` |
| `cluster-onboarding-gitops` | Creates ArgoCD projects for teams | `teams` list |
| `cluster-onboarding-namespaces` | Creates team namespaces with quotas and policies | `teams` list |

Each cluster is defined by a directory under `clusters/<env>/<name>/` containing:

- **conf.yaml** — cluster identity, chart lists, deploy toggles, team assignments
- **platform-config.yaml** — values for platform-config charts
- **operator-instances.yaml** — values for operator CR charts
- **operator-deployment.yaml** — values for operator Subscriptions
- **provision.yaml** — provisioning values (if deploying a new cluster)

### Values precedence

```
chart defaults (values.yaml)
  → env/<env>/conf.yaml + env/<env>/platform-config.yaml
  → clusters/<env>/<name>/conf.yaml + clusters/<env>/<name>/platform-config.yaml
```

More specific files override less specific ones. Missing files are silently skipped.

### Adding a chart to a cluster

1. Add the chart name to `platformCharts` or `operatorInstanceCharts` in the cluster's `conf.yaml`
2. Set values in the corresponding values file (`platform-config.yaml` or `operator-instances.yaml`)
3. Push to git — ArgoCD creates an Application and syncs it

All chart features default to `include: false`. Enable them explicitly.

## Documentation

- [Cluster Provisioning](docs/cluster-provisioning/) — AWS, vSphere, baremetal, platform-none, hybrid vSphere CP
- [Cluster Configuration](docs/cluster-configuration/) — ApplicationSets, Helm charts, values precedence
- [Day 2 cluster configuration guide](docs/day2-cluster-config/) — what to enable on each cluster, organized by priority tier
- [Reference values files](docs/reference/) — fully-commented example files for defining a new cluster

## Public repository

A sanitized copy of this repo is published to [ocp-cluster-automation](https://github.com/blediagolli/ocp-cluster-automation). A GitHub Action runs nightly to replace org-specific values with `YOUR_*` placeholders and secrets with `CHANGEME_*` placeholders. See `.github/workflows/sync-release.yml`.

## License

Apache 2.0 — see [LICENSE](LICENSE).
