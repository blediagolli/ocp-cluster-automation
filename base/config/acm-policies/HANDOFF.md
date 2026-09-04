# acm-policies — Handoff

**Created:** 2026-09-04 (gap analysis)

## What it does

Deploys ACM Policy and PlacementRule resources for multi-cluster governance. Six policy templates:
- **pod-security** — Pod Security Standards enforcement (restricted/baseline/privileged)
- **network-isolation** — Default-deny NetworkPolicy in user namespaces
- **resource-quotas** — Ensures ResourceQuotas exist in user namespaces
- **compliance-operator** — Ensures Compliance Operator is installed on target clusters
- **image-policy** — Restricts container images to allowed registries
- **etcd-encryption** — Verifies etcd encryption is enabled

Each policy has independent `include` toggle, severity, remediationAction (inform/enforce), namespace selectors, and cluster placement selectors.

## Current state

- **New chart, not enabled on any cluster**
- All six policies disabled by default
- Not yet added to any ApplicationSet

## Outstanding

- Requires ACM hub — add to hub-only section of `cluster-config.yaml`
- Test each policy individually in inform mode before switching to enforce
- Customize placement selectors to match actual cluster labels
