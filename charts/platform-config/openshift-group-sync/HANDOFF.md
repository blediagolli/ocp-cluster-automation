# openshift-group-sync — Handoff

**Date:** 2026-09-16

## What it does
CronJob that synchronizes identity provider groups into OpenShift Group objects. Supports two providers:
- **LDAP** — runs `oc adm groups sync` with RFC2307 schema against an LDAP/AD server
- **Keycloak** — calls the Keycloak admin REST API to fetch groups and members, then creates/updates OpenShift Groups via `oc`

RBAC is scoped to `user.openshift.io/groups` only (not cluster-admin).

## What was done
- Refactored from LDAP-only to multi-provider (`groupSync.provider: ldap|keycloak`)
- Extracted shared RBAC into `rbac.yaml` with a least-privilege ClusterRole
- Added Keycloak CronJob that authenticates via client_credentials grant, fetches groups/members from the admin API, and syncs into OpenShift Group objects
- Supports optional group name mappings (`groupMappings`) for both providers
- Wired to aws-test pointing at the hub Keycloak (sso realm), mapping `admins` and `users` groups

## Current state
- **LDAP**: not deployed anywhere — needs LDAP server to test
- **Keycloak**: enabled on aws-test — requires `keycloak-group-sync` Secret with `client-id` and `client-secret` keys (service account client with `realm-management/view-users` role)

## Prerequisites
- For Keycloak: create a service-account client in Keycloak with `realm-management` → `view-users` role, then create the credentials Secret (or use ExternalSecrets)
- For LDAP: bind password Secret and CA ConfigMap

## Testing
- **helm-unittest**: `helm unittest charts/platform-config/openshift-group-sync` — 25 tests covering RBAC, LDAP CronJob, and Keycloak CronJob templates
- **Helm test hook**: `helm test <release>` — in-cluster pod validates SA, ClusterRole, CRB, CronJob, ConfigMap, and Secret exist
- **E2E script**: `charts/platform-config/openshift-group-sync/tests/e2e-test.sh [provider] [namespace]` — validates deployed resources and last job status

## Outstanding
- `keycloak-group-sync` Secret needs to be provisioned on aws-test (ExternalSecret or manual)
- LDAP provider untested
- Consider pruning stale groups that no longer exist in the identity provider
