# Reference Values Files

Fully-commented example files for defining a cluster. Copy these to your cluster
directory and enable the sections you need.

## Quick start

```bash
# 1. Create the cluster directory
mkdir -p clusters/dev/my-cluster

# 2. Copy the files you need
cp docs/reference/conf.yaml              clusters/dev/my-cluster/
cp docs/reference/platform-config.yaml   clusters/dev/my-cluster/
cp docs/reference/operators.yaml         clusters/dev/my-cluster/

# 3. (Optional) Copy provisioning values if deploying via ACM/Hive
cp docs/reference/provision.yaml         clusters/dev/my-cluster/

# 4. Edit each file — set cluster.name, cluster.baseDomain, enable features
# 5. Commit and push — ArgoCD picks up the new cluster automatically
```

## Files

| File | Controls | ApplicationSet |
|------|----------|----------------|
| `conf.yaml` | Cluster identity, chart lists, deploy toggles, team membership | All — drives ApplicationSet generation |
| `platform-config.yaml` | Day-2 platform configuration (31 charts: TLS, OAuth, etcd, RBAC, etc.) | `cluster-platform-config` |
| `operators.yaml` | Operators: the OLM Subscription and the CRs, per operator | `cluster-operators` |
| `provision.yaml` | ACM/Hive cluster provisioning (AWS, vSphere, baremetal, platform-none) | `cluster-provisioning` |

## How it works

**conf.yaml** is the cluster identity file. The `platformCharts` and
`operatorCharts` lists control which ArgoCD Applications are generated.
Removing a chart from the list removes its Application (but
`preserveResourcesOnDeletion` keeps the cluster-side resources intact).

The other files provide **values** to those Applications. Every feature
defaults to `include: false` — nothing deploys until you explicitly enable it.

### Values precedence

```
chart defaults (values.yaml)
  < env/<env>/conf.yaml
  < env/<env>/<category>.yaml        (platform-config, operators, etc.)
  < clusters/<env>/<name>/conf.yaml
  < clusters/<env>/<name>/<category>.yaml
```

Environment-level files set defaults for all clusters in that environment.
Cluster-level files override per-cluster. You only need to set values that
differ from the defaults.

## Conventions

- **`include: false`** — every feature is off by default. Set `include: true`
  to enable.
- **`YOUR_*`** placeholders — replace with your org-specific values (domains,
  bucket names, AWS resource IDs).
- **`CHANGEME_*`** placeholders — replace with actual secrets (passwords,
  tokens, API keys). These should be managed via ExternalSecrets or
  SealedSecrets in production.
- **`example.com`** — replace with your actual base domain.
- **Commented-out sections** — alternative configurations (e.g., vSphere vs AWS
  in provision.yaml). Uncomment the one you need, delete the rest.

## Tier organization

All files organize features into three tiers matching the
[day-2 configuration guide](../day2-cluster-config/README.md):

| Tier | Meaning |
|------|---------|
| **Critical** | Enable on every cluster — TLS, API server, ingress, OAuth, image registry, pull secrets, machine config |
| **Recommended** | Enable on most clusters — etcd backup, monitoring, RBAC, ACS, compliance, logging |
| **Nice to Have** | Enable based on workload needs — storage, virtualization, service mesh, policy admission |

## What you don't need

- **`operators.yaml`** — skip if your environment-level file already configures
  the operators you need. Only copy this if you need cluster-specific overrides.
- **`provision.yaml`** — only needed for clusters provisioned via ACM/Hive
  (`deployProvision: true`). Skip for pre-existing clusters.
- **`operators/<chart>.yaml`** — only needed when one operator's block would
  drown the others in the shared `operators.yaml`. Start in the shared file; the
  shape is identical, so moving later is a cut-and-paste.
