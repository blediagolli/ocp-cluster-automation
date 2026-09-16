# group-sync (operator instance) — Handoff

**Date:** 2026-09-16

## What it does
Deploys a `GroupSync` CR for the redhat-cop group-sync-operator. The operator handles the full lifecycle of syncing groups from external identity providers into OpenShift Group objects. Supports Keycloak and LDAP providers, including running both simultaneously.

## What was done
- Created chart with GroupSync CR supporting multiple providers via `providers` list
- Added `group-sync-operator` to operator-deployment values (community-operators, alpha channel)
- Keycloak provider: configurable realm, loginRealm, scope, CA, credentials
- LDAP provider: RFC2307 schema with configurable group/user queries, CA, credentials

## Current state
- **Not deployed** — available as an alternative to the platform-config CronJob approach
- Use this when you want the operator to manage the sync lifecycle (status reporting, retry, operator upgrades) instead of a raw CronJob

## Prerequisites
- `group-sync-operator` must be enabled in operator-deployment
- For Keycloak: Secret with `username` and `password` keys for a Keycloak service account
- For LDAP: Secret with `username` (bindDN) and `password` (bindPassword) keys

## Testing
- **helm-unittest**: `helm unittest charts/operator-instances/group-sync` — 11 tests covering guard, metadata, keycloak/LDAP providers, CA toggle, multi-provider, and empty providers
- **Helm test hook**: `helm test <release>` — in-cluster pod validates GroupSync CR status, operator pod, and OpenShift Groups
- **E2E script**: `charts/operator-instances/group-sync/tests/e2e-test.sh [name] [namespace]` — validates operator pod, CR status, providers, and synced Groups

## Outstanding
- Not wired to any cluster yet — add to `operatorInstanceCharts` in conf.yaml when ready
- The operator also supports Azure AD, GitHub, and GitLab providers — add to template as needed
