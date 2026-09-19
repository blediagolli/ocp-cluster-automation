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
clusters/           # Per-cluster config (conf.yaml, platform-config.yaml, operator-instances.yaml)
  mgt/acm-hub/     # Management / hub cluster
  dev/              # Development environment clusters
env/                # Environment-level defaults (dev, prod)
charts/             # Helm charts for platform configuration
  platform-config/  # Day-2 platform charts (oauth, tls, rbac, monitoring, ...)
  operator-instances/ # Operator CR charts (ACS, cert-manager, Keycloak, Quay, ...)
base/               # ArgoCD Applications, ApplicationSets, bootstrap
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
| `YOUR_CLUSTER_ISSUER` | cert-manager ClusterIssuer name |
| `YOUR_STORAGE_CLASS` | Default storage class on the hub |
| `YOUR_IMAGE_REGISTRY_BUCKET` | S3 bucket for the internal image registry |
| `CHANGEME_*` | Secrets — generate new values and store in Vault |

3. Bootstrap the hub cluster:
   ```bash
   oc apply -k clusters/mgt/acm-hub/bootstrap/
   ```

4. Add managed clusters by creating directories under `clusters/<env>/<name>/`

## Documentation

- [Cluster Provisioning](docs/cluster-provisioning/) — AWS, vSphere, baremetal, platform-none, hybrid vSphere CP
- [Cluster Configuration](docs/cluster-configuration/) — ApplicationSets, Helm charts, values precedence
- [Day 2 cluster configuration guide](docs/day2-cluster-config/) — what to enable on each cluster, organized by priority tier
- [Reference values files](docs/reference/) — fully-commented example files for defining a new cluster

## License

Apache 2.0
