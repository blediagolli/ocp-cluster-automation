# quay-registry — Handoff

## What it does
Deploys a Red Hat Quay registry instance via the `QuayRegistry` CR with Keycloak OIDC authentication, production-hardened config, and Quay Bridge operator integration for automatic namespace-to-organization syncing.

## Current state
- **Enabled** on `mgt/acm-hub` cluster
- Quay registry running with minimal resources (test cluster sizing)
- Keycloak OIDC configured via `sso` realm, client `quay`
- Quay Bridge operator deployed and verified working — creates Quay orgs for opted-in namespaces
- `namespaceCreationDefault` configurable via `bridge.namespaceCreationDefault` (default false)
- Config bundle uses operator-managed Clair (no FEATURE_SECURITY_SCANNER in bundle)
- Action log rotation enabled, archiving to ODF/RHOCSStorage via `local_us` location
- Monitoring disabled (operator requires AllNamespaces install mode)
- HPA and mirror disabled for test cluster

## Templates
- `quayregistry.yaml` — QuayRegistry CR with minimal resources, single replica
- `config-bundle-secret.yaml` — Production config with Keycloak OIDC, rate limits, quota management, team syncing
- `quay-bridge.yaml` — QuayIntegration CR + OAuth token secret, comprehensive namespace denylist
- `namespace.yaml` — quay-enterprise namespace (disabled on hub — operators app owns it)

## Key values
- `quayRegistry.bridge.oauthToken` — OAuth app token with super:user scope (NOT a robot account)
- `quayRegistry.bridge.namespaceCreationDefault` — auto-create Quay orgs for all non-denylisted namespaces
- `quayRegistry.actionLogRotation.include` — enable action log rotation with archive path
- `quayRegistry.keycloak.*` — OIDC server URL must end with trailing `/`
- `quayRegistry.superUsers` — list of super user usernames

## Outstanding
- Clean up stale DB entries from OAuth token troubleshooting (openshift org, robot account, OAuth app)
- Consider enabling monitoring when operator is deployed in AllNamespaces mode
- Resource requests are minimal (test sizing) — needs production sizing for real workloads
