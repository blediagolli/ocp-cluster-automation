# openshift-gitops-instance — Handoff

**Modified:** 2026-09-11

## What it does
Deploys the ArgoCD CR for the platform GitOps instance, an AppProject for platform charts, a ClusterRoleBinding for cluster-admin access, and the GitOps console plugin. Each component is independently toggled (`argocd.include`, `appProject.include`, `clusterRoleBinding.include`, `consolePlugin.include`).

## Current state
- **Enabled** on hub only
- ArgoCD CR running with HA disabled, resource exclusions for Tekton TaskRun/PipelineRun
- AppProject `platform` scoped to the gitops-for-organizations repo

## Gotchas
- RBAC `defaultPolicy: role:admin` grants admin to all authenticated users — tighten for production
- `resourceExclusions` for Tekton prevents ArgoCD from tracking ephemeral pipeline runs
- Console plugin requires the GitOps operator to register the plugin with the console

## Testing

**Helm test** (`helm test <release>`): Checks ArgoCD CR is Available and AppProject exists. ArgoCD does not run Helm test hooks — use for local validation only.

**E2E script** (`tests/e2e-test.sh`):
- Validates ArgoCD pods are running in openshift-gitops
- Checks ArgoCD route is accessible
- Verifies AppProject `platform` exists with correct source repos
- Confirms ClusterRoleBinding for cluster-admin access
