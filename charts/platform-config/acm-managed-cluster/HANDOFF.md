# acm-managed-cluster — Handoff

**Modified:** 2026-09-08

## What it does
Registers a managed cluster with ACM hub. Creates: ManagedCluster, KlusterletAddonConfig, ManagedClusterAddons, auto-import Secret (kubeconfig or token mode), and ArgoCD cluster secret registration.

## What changed this session
- Added `argocd-cluster-secret.yaml` — PostSync Job that reads the kubeconfig secret and creates an ArgoCD cluster secret in `openshift-gitops` namespace. ACM 2.17 no longer creates the legacy `application-manager-cluster-secret`, so this is needed for the GitOpsCluster/Placement integration to register managed clusters in ArgoCD.
- Renamed dev cluster from `dev.example.com` to `cluster-lz5bn` (namespace compat — no dots allowed)

## Current state
- Used via the `cluster-import` ApplicationSet (separate from `cluster-config`)
- Hub cluster `local-cluster` auto-imported
- Dev cluster `cluster-lz5bn` imported and Joined/Available via ACM

## Outstanding
- Auto-import secret contains credentials — `kubeconfig` and `token` values should use sealed-secrets or external-secrets
- No cluster destroy/detach — removing a cluster from conf.yaml leaves ManagedCluster orphaned; needs prune policy
- Token mode (`autoImport.mode: token`) does not trigger the ArgoCD register Job — only kubeconfig mode is wired
