# acm-managed-cluster — Handoff

## What it does
Registers a managed cluster with ACM hub. Creates: ManagedCluster, KlusterletAddonConfig, ManagedClusterAddons, and optional auto-import Secret (kubeconfig or token mode).

## Current state
- **Not modified this session** — pre-existing chart
- Used via the `cluster-import` ApplicationSet (separate from `cluster-config`)
- Hub cluster has it enabled; import applications exist for dev and prod clusters
- Templates are well-parameterized with flexible label support and addon toggles

## Outstanding
- **Auto-import secret contains credentials** — `kubeconfig` and `token` values are in conf.yaml; ensure these aren't committed in plaintext (use sealed-secrets or external-secrets)
- **No cluster destroy/detach** — Removing a cluster from conf.yaml leaves the ManagedCluster resource orphaned; needs manual cleanup or ArgoCD prune policy
- **Missing cluster proxy toggle** — `clusterProxy` addon is `false` by default but needed for remote cluster access (dev cluster uses it)
- **Consider clusterClaim labels** — Could add ClusterClaim resources for dynamic placement rule matching
