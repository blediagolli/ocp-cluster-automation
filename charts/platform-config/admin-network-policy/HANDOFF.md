# admin-network-policy — Handoff

**Created:** 2026-09-04 (deep dive agents)

## What it does

Deploys `AdminNetworkPolicy` resources — cluster-scoped network policies that apply across namespaces. Values define a list of policies, each with priority, subject namespace selector, and ingress/egress rules.

Default policies included (all `include: false`):
- `allow-monitoring` (priority 10) — permits Prometheus scraping from `openshift-monitoring` on ports 9090/9091/8443
- `allow-ingress-controller` (priority 20) — permits router pod traffic on ports 8080/8443

## Current state

- **Enabled on aws-test** — both `allow-monitoring` and `allow-ingress-controller` policies active
- Fixed template bug: empty `matchLabels` now renders `matchLabels: {}` instead of null

## Outstanding

- Consider adding a default-deny baseline AdminNetworkPolicy
