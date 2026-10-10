# OCP Cluster Automation

A production-ready GitOps framework for provisioning and configuring OpenShift
clusters at scale using Red Hat ACM, OpenShift GitOps (ArgoCD), and Helm.

## Overview

This repository implements a complete cluster lifecycle:

1. **Provision** — ACM + Hive create clusters from `clusters/<env>/<name>/provision.yaml`
2. **Configure** — ArgoCD ApplicationSets deploy platform Helm charts per cluster
3. **Operate** — Day-2 operators, policies, and team onboarding via git commits

## Repository layout

```
clusters/                 # Per-cluster config (conf.yaml, platform-config.yaml, ...)
  mgt/acm-hub/            # Management / hub cluster
    bootstrap/            # Kustomize entrypoint — ArgoCD + ACM install
    applications/         # ArgoCD Applications
    applicationsets/      # ApplicationSets that fan out to managed clusters
  dev/                    # Development environment clusters
env/                      # Environment-level defaults (dev, prod, mgt)
charts/                   # Helm charts
  platform-config/        # Day-2 platform charts (oauth, tls, rbac, monitoring, ...)
  operators/              # One chart per operator: Subscription + its CRs
  cluster-provisioning/   # Hive ClusterDeployment + provisioning jobs
  onboarding/             # Team namespace and GitOps onboarding
teams/                    # Team definitions consumed by the onboarding charts
docs/                     # Guides and fully-commented reference values files
```

## Prerequisites

- OpenShift 4.x cluster (hub)
- Red Hat ACM (Advanced Cluster Management)
- OpenShift GitOps (ArgoCD)
- cert-manager with a ClusterIssuer
- HashiCorp Vault or External Secrets Operator (for production secrets)

## Getting started

1. Fork this repository
2. Search for placeholder values and replace them with your configuration:

| Placeholder | Description |
|---|---|
| `YOUR_ORG` | Your GitHub org or username |
| `CLUSTER_DOMAIN` | Your hub cluster domain (e.g. `apps.hub.example.com`) |
| `example.com` | Your base domain for managed clusters |
| `your-email@example.com` | Admin email for Let's Encrypt / notifications |
| `YOUR_HOSTED_ZONE_ID` | Route53 hosted zone ID (if using AWS DNS) |
| `YOUR_CLUSTER_ISSUER` | cert-manager ClusterIssuer name (e.g. `letsencrypt`) |
| `YOUR_STORAGE_CLASS` | StorageClass for charts that provision storage |
| `YOUR_IMAGE_REGISTRY_BUCKET` | S3 bucket for the internal image registry |
| `YOUR_CLUSTER_IMAGE_SET` | ClusterImageSet to provision from (`oc get clusterimageset`) |
| `AAAAYOUR_SSH_PUBLIC_KEY` | Public half of your node SSH key pair |
| `CHANGEME_*` | Secrets — generate new values and store in Vault |

3. Fill in the values files for your hub and your clusters (see below)

4. Bootstrap the hub cluster:
   ```bash
   oc apply -k clusters/mgt/acm-hub/bootstrap/
   ```

5. Add managed clusters by creating directories under `clusters/<env>/<name>/`

## The values files are empty on purpose

This repository ships the structure, not a configuration. Every values file
under `clusters/` and `env/` — `platform-config.yaml`, `operators.yaml`,
`operators/<operator>.yaml`, `provision.yaml`, `namespace-sizes.yaml` — arrives
empty, with a header naming the precedence chain and pointing at the reference
file that documents its fields. Fill in what your environment needs.

Two kinds of file do carry content, because they are structure rather than
configuration:

- `clusters/<env>/<name>/conf.yaml` — the cluster identity the ApplicationSet
  generators key off, and the `platformCharts` / `operatorCharts` lists
  that decide which Applications exist at all. Both lists are empty: which
  charts a cluster runs is your decision. Every chart in the repo is listed
  beneath them commented out, so picking one is uncommenting a line.
- `clusters/mgt/acm-hub/bootstrap.yaml` — the input to the hub bootstrap script.

A fresh clone therefore deploys nothing. That is the intended starting point:
fill in `conf.yaml` to choose charts, then fill in the values files those
charts read.

`docs/reference/` holds a fully-commented example of every values file, and
each chart's own `values.yaml` holds its defaults. Between them, nothing you
need is missing — it is just not pre-decided for you.

## Documentation

- [Cluster Provisioning](docs/cluster-provisioning/) — AWS, vSphere, baremetal, platform-none, hybrid vSphere CP
- [Cluster Configuration](docs/cluster-configuration/) — ApplicationSets, Helm charts, values precedence
- [Day 2 cluster configuration guide](docs/day2-cluster-config/) — what to enable on each cluster, organized by priority tier
- [Reference values files](docs/reference/) — fully-commented example files for defining a new cluster

## License

Apache 2.0
