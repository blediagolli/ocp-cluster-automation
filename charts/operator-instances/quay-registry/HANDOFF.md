# quay-registry — Handoff

## What it does
Deploys a Red Hat Quay registry instance via the `QuayRegistry` CR with full config bundle management, optional OIDC authentication, external database/storage support, infra node scheduling, Quay Bridge operator integration, and an init job for org/robot creation via the Quay REST API.

## Current state
- **Enabled** on `mgt/acm-hub` cluster
- All values nested under single `quayRegistry:` root key
- Everything togglable via `include` flags following repo pattern
- 11 components individually togglable via `managed: true/false`
- Keycloak OIDC configured via `sso` realm, client `quay`
- Quay Bridge operator deployed with comprehensive namespace denylist
- Config bundle uses operator-managed Clair (no FEATURE_SECURITY_SCANNER in bundle)
- Action log rotation enabled on hub
- Monitoring and HPA disabled for test cluster

## Templates
- `quayregistry.yaml` — QuayRegistry CR with all 11 components, per-component overrides (replicas, resources, affinity, tolerations, volumeSize), infra scheduling injection
- `config-bundle-secret.yaml` — Config bundle with all feature flags, OIDC, external DB/storage, custom TLS certs
- `quay-bridge.yaml` — QuayIntegration CR + OAuth token secret, hostname auto-derived from baseDomain
- `init-job.yaml` — PostSync hook Job that creates organizations and robot accounts via REST API
- `namespace.yaml` — quay-enterprise namespace (togglable via `createNamespace`)

## Value structure
```
quayRegistry:
  include/name/namespace/createNamespace
  config:           # feature flags, quotas, tag expiration, team syncing, etc.
  components:       # 11 components with managed/replicas/resources
    quay/clair/clairPostgres/postgres/objectstorage/redis/hpa/route/mirror/monitoring/tls
  scheduling:       # infra node affinity + tolerations (applied to all managed components)
  customTls:        # BYO ssl.cert/ssl.key (auto-disables TLS component)
  externalDatabase: # DB_URI (auto-disables postgres component)
  externalStorage:  # DISTRIBUTED_STORAGE_CONFIG (auto-disables objectstorage component)
  oidc:             # OIDC provider config (auto-disables FEATURE_DIRECT_LOGIN)
  bridge:           # QuayIntegration CR with denylist
  init:             # PostSync job for org/robot creation
```

## Auto-toggle behavior
- `externalStorage.include: true` → objectstorage component forced to `managed: false`
- `externalDatabase.include: true` → postgres component should be set to `managed: false` manually (DB_URI rendered in bundle)
- `customTls.include: true` → TLS component forced to `managed: false`, ssl.cert/ssl.key added to secret
- `oidc.include: true` → `FEATURE_DIRECT_LOGIN: false`
- `components.mirror.managed: true` → `FEATURE_REPO_MIRROR: true` in config bundle

## Key values
- `quayRegistry.bridge.oauthToken` — OAuth app token with super:user scope (NOT a robot account)
- `quayRegistry.oidc.server` — OIDC server URL must end with trailing `/`
- `quayRegistry.oidc.provider` — provider name (default `keycloak`), uppercased for config key (e.g. `KEYCLOAK_LOGIN_CONFIG`)
- `quayRegistry.init.oauthToken` — OAuth token for REST API calls (stored in Secret, not embedded)
- `quayRegistry.config.quotas.defaultSystemRejectBytes` — uses `| int64` to avoid scientific notation

## Testing

Helm template validation:
```bash
# Minimal
helm template test charts/operator-instances/quay-registry/ --set quayRegistry.include=true

# All features
helm template test charts/operator-instances/quay-registry/ \
  --set quayRegistry.include=true \
  --set quayRegistry.scheduling.include=true \
  --set quayRegistry.oidc.include=true --set quayRegistry.oidc.server=https://sso.example.com/realms/quay/ --set quayRegistry.oidc.clientSecret=x \
  --set quayRegistry.externalDatabase.include=true --set quayRegistry.externalDatabase.host=db --set quayRegistry.externalDatabase.username=u --set quayRegistry.externalDatabase.password=p \
  --set quayRegistry.externalStorage.include=true \
  --set quayRegistry.customTls.include=true \
  --set quayRegistry.bridge.include=true --set quayRegistry.bridge.oauthToken=x \
  --set quayRegistry.init.include=true --set quayRegistry.init.quayUrl=https://r --set quayRegistry.init.oauthToken=x \
  --set cluster.baseDomain=apps.example.com
```

E2E bridge test: `./tests/e2e-bridge-test.sh <quay-host> <token>`

## Verified (2026-09-09)
Full e2e test passed on `mgt/acm-hub`:
1. Created namespace `quay-e2e-test` with bridge opt-in label
2. Bridge auto-created Quay org and provisioned dockerconfigjson secrets for all SAs
3. `oc new-build` built image, pushed to Quay via ImageStream
4. Deployment pulled image back from Quay successfully
5. Namespace deletion triggered bridge cleanup of Quay org

## Verified — Init Job (2026-09-16)
Init job PostSync hook tested on `mgt/acm-hub`:
1. Health check passed (`"status_code":200` grep)
2. Created 3 orgs: platform, team-alpha, team-beta (all with 10GB quota)
3. Created 2 robot accounts: platform+cicd, platform+pull
4. Idempotent rerun: "already exists" errors are non-fatal (curl returns 0)
5. Job completed in 6 seconds

## Outstanding
- Consider enabling monitoring when operator is deployed in AllNamespaces mode
- Resource requests are minimal (test sizing) — needs production sizing for real workloads
