# namespace-config — Handoff

**Modified:** 2026-09-10

## What it does
Provisions team namespaces with t-shirt sized ResourceQuotas and LimitRanges. Creates per namespace:
- Namespace with `argocd.argoproj.io/managed-by: <team>-gitops` label
- ResourceQuota (`team-quota`) sized by `namespaceSizes` definitions
- LimitRange (`team-limits`) with container defaults, min, max
- PreSync cleanup Job that removes stale default/named quotas and limits

## Current state
- Deployed via `onboarding-namespaces` ApplicationSet using matrix generator (conf.yaml `teams` list)
- team-alpha and team-beta onboarded to dev cluster, both Synced/Healthy
- Namespaces are environment-scoped — only `team.namespaces.<env>` entries are created on each cluster
- Auto-prune enabled — removing a namespace from the list deletes it from the cluster

## Key values
- `team.namespaces.<env>` — list of `{name, size}` objects; chart selects using `cluster.environment`
- `namespaceSizes` — t-shirt size definitions (small, medium, large) with quota and limit specs
- Sizes can be overridden at env level (`env/<env>/namespace-sizes.yaml`) or cluster level

## Gotchas
- PreSync cleanup Job deletes quotas/limits named `default`, `small`, `medium`, `large` — prevents conflicts when resizing
- `managed-by` label on namespaces grants the team's ArgoCD instance permission to deploy into them
