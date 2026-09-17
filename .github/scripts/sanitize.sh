#!/usr/bin/env bash
set -euo pipefail

# Sanitize the working tree: remove org-specific values, secrets, and dev-only
# files so the result can be published to a public repository.
#
# All replaceable values are read from environment variables. Source
# .github/sanitize.env for defaults, then override with GitHub secrets at
# runtime. Can be run locally for testing:
#
#   source .github/sanitize.env
#   export STACKROX_OIDC_SECRET=... # real secret values
#   .github/scripts/sanitize.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

# ---------- validate required env vars ----------
required_vars=(
  GIT_ORG
  HUB_CLUSTER_DOMAIN
  DEV_BASE_DOMAIN
  USER_EMAIL
  HOSTED_ZONE_ID
  CLUSTER_ISSUER_NAME
  HUB_STORAGE_CLASS
  IMAGE_REGISTRY_BUCKET
  UPSTREAM_ORG
  STACKROX_OIDC_SECRET
  QUAY_OIDC_SECRET
  QUAY_BRIDGE_TOKEN
  QUAY_INIT_TOKEN
  KEYCLOAK_ADMIN_PASSWORD
  KEYCLOAK_USER_PASSWORD
  OPENSHIFT_OIDC_SECRET
)

missing=()
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: missing required environment variables:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

# ---------- 1. remove non-release files/directories ----------
echo "==> Removing non-release files..."

find . -name 'HANDOFF.md' -delete
find . -name 'CLAUDE.md' -delete

rm -rf .claude
rm -rf terraform tools
rm -f docs/architecture-operator-cr-coupling.md
rm -f scripts/COMPLIANCE-REPORT-NEXT.md charts/cluster-provisioning/aws-platform-none-design.md
rm -f scripts/ai-common.sh scripts/ai-fix scripts/ai-implement scripts/ai-plan \
      scripts/ai-research scripts/ai-review scripts/ai-run scripts/bootstrap-ai-dev.sh

# remove non-release clusters
rm -rf clusters/dev/cluster-lz5bn*
rm -rf clusters/prod/cluster-m6tk9*
rm -rf clusters/prod/aws-none-prod

# ---------- 2. rename aws-test → example-cluster ----------
echo "==> Renaming aws-test cluster..."

if [[ -d clusters/dev/aws-test ]]; then
  mv clusters/dev/aws-test clusters/dev/example-cluster
fi

# ---------- 3. bulk string replacements (non-secret, org-specific) ----------
echo "==> Applying string replacements..."

# Build a sed expression file for portability (handles GNU and BSD sed)
SED_SCRIPT=$(mktemp)
trap 'rm -f "$SED_SCRIPT"' EXIT

cat > "$SED_SCRIPT" <<SEDEOF
s|git@github.com:${GIT_ORG}/gitops-for-organizations|git@github.com:YOUR_ORG/ocp-cluster-automation|g
s|git@github.com:${GIT_ORG}/|git@github.com:YOUR_ORG/|g
s|https://github.com/${GIT_ORG}/gitops-for-organizations|https://github.com/YOUR_ORG/ocp-cluster-automation|g
s|https://github.com/${GIT_ORG}/|https://github.com/YOUR_ORG/|g
s|https://github.com/${UPSTREAM_ORG}/gitops-for-organizations|https://github.com/YOUR_ORG/ocp-cluster-automation|g
s|https://github.com/${UPSTREAM_ORG}/|https://github.com/YOUR_ORG/|g
s|${HUB_CLUSTER_DOMAIN}|CLUSTER_DOMAIN|g
s|${DEV_BASE_DOMAIN}|example.com|g
s|${USER_EMAIL}|your-email@example.com|g
s|${HOSTED_ZONE_ID}|YOUR_HOSTED_ZONE_ID|g
s|${CLUSTER_ISSUER_NAME}|YOUR_CLUSTER_ISSUER|g
s|${HUB_STORAGE_CLASS}|YOUR_STORAGE_CLASS|g
s|${IMAGE_REGISTRY_BUCKET}|YOUR_IMAGE_REGISTRY_BUCKET|g
s|aws-test|example-cluster|g
SEDEOF

# ---------- 4. secret replacements ----------
cat >> "$SED_SCRIPT" <<SEDEOF
s|${STACKROX_OIDC_SECRET}|CHANGEME_STACKROX_OIDC_CLIENT_SECRET|g
s|${QUAY_OIDC_SECRET}|CHANGEME_QUAY_OIDC_CLIENT_SECRET|g
s|${QUAY_BRIDGE_TOKEN}|CHANGEME_QUAY_BRIDGE_OAUTH_TOKEN|g
s|${QUAY_INIT_TOKEN}|CHANGEME_QUAY_INIT_OAUTH_TOKEN|g
s|${KEYCLOAK_ADMIN_PASSWORD}|CHANGEME_KEYCLOAK_ADMIN_PASSWORD|g
s|${KEYCLOAK_USER_PASSWORD}|CHANGEME_KEYCLOAK_USER_PASSWORD|g
s|${OPENSHIFT_OIDC_SECRET}|CHANGEME_OPENSHIFT_OIDC_CLIENT_SECRET|g
SEDEOF

# Apply to all text files (skip binary, .git, images)
find . \
  -path ./.git -prune -o \
  -path './img' -prune -o \
  -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.md' -o -name '*.sh' -o -name '*.json' -o -name '*.txt' -o -name '*.gitignore' \) \
  -print0 |
while IFS= read -r -d '' file; do
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' -f "$SED_SCRIPT" "$file"
  else
    sed -i -f "$SED_SCRIPT" "$file"
  fi
done

# ---------- 5. rewrite README for public consumption ----------
echo "==> Rewriting README..."

cat > README.md <<'READMEEOF'
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
READMEEOF

# ---------- 6. clean up .gitignore for public repo ----------
cat > .gitignore <<'IGNEOF'
.DS_Store
*.swp
*.swo
*~
.claude/settings.local.json
IGNEOF

echo "==> Sanitization complete."
