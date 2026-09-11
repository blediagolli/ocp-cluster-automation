# application-gitops — Handoff

**Modified:** 2026-09-10

## What it does
Provisions a team's ArgoCD instance on a target cluster. Creates:
- `<team>-gitops` namespace
- ArgoCD CR with route, RBAC for team admins group
- AppProject scoped to team's environment-specific namespaces + gitops namespace
- RoleBinding granting team admins `admin` on the gitops namespace

## Current state
- Deployed via `onboarding-gitops` ApplicationSet using matrix generator (conf.yaml `teams` list)
- team-alpha and team-beta onboarded to dev cluster, both Synced/Healthy
- AppProject destinations are environment-scoped — only namespaces from `team.namespaces.<env>` are allowed

## Key values
- `team.name` — team identifier, used for namespace and ArgoCD naming
- `team.admins` — LDAP/OIDC group granted ArgoCD admin role
- `team.repo` — git repo the AppProject allows as a source
- `team.namespaces.<env>` — environment-scoped namespace list; chart selects using `cluster.environment`

## Values precedence
`teams/<team>.yaml` < `env/<env>/conf.yaml` < `env/<env>/teams/<team>.yaml` < `clusters/.../conf.yaml` < `clusters/.../teams/<team>.yaml`

## Testing

**Helm test** (`helm test <release>`): Checks ArgoCD instance and AppProject exist in team's gitops namespace. ArgoCD does not run Helm test hooks — use for local validation only.

**E2E script** (`tests/e2e-test.sh <team-name>`):
- Validates `<team>-gitops` namespace exists
- Checks ArgoCD CR is Available with running pods
- Verifies AppProject has correct source repos and namespace destinations
- Confirms RoleBinding grants admin to team admins group
