# rbac

Centralized RBAC management for platform-level ClusterRoles, Roles, ClusterRoleBindings, and RoleBindings.

**App-specific RBAC should live in the app's own chart. OAuth-related group bindings stay in openshift-oauth.**

## What it does

Manages four RBAC resource types, each gated by a top-level `include` toggle and per-item `include`:

- **ClusterRoles** — custom cluster-wide roles (e.g., read-only-nodes, namespace-viewer)
- **Roles** — custom namespace-scoped roles
- **ClusterRoleBindings** — bind Groups, Users, or ServiceAccounts to ClusterRoles cluster-wide
- **RoleBindings** — bind subjects to a ClusterRole or Role within a namespace

## Subject types

All three Kubernetes subject types are supported:
- `Group` — OpenShift groups (from LDAP sync, OIDC, or manual)
- `User` — individual user accounts
- `ServiceAccount` — requires `namespace` field

The template automatically sets `apiGroup` based on subject kind.

## RoleBinding roleRef

RoleBindings accept either `clusterRole` or `role` (mutually exclusive). The template sets `roleRef.kind` accordingly.

## Current state
- **Enabled on aws-test** — `cluster-viewer` ClusterRole bound to `team-alpha` and `team-beta` Groups
- `cluster-viewer` provides read-only access to nodes, namespaces, PVs, events, storage classes, machines, and `config.openshift.io` resources

## Deployment

Add `- chart: rbac` to `platformCharts` in the cluster's conf.yaml. Override values at env or cluster level as needed.

## Testing

```bash
# Lint
helm lint charts/platform-config/rbac/

# Template render
helm template test charts/platform-config/rbac/ -f <values-file>

# Helm test (on-cluster, run via ArgoCD or helm test)
# templates/tests/test-connection.yaml — validates all included resources exist via oc get

# E2E test (shell)
./charts/platform-config/rbac/tests/e2e-test.sh                  # basic cluster checks
./charts/platform-config/rbac/tests/e2e-test.sh <values-file>    # validates specific resources from values
```
