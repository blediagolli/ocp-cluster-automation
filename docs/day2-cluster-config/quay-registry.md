# Quay Registry Setup

The `quay-registry` chart deploys a QuayRegistry CR, config bundle, optional Quay Bridge integration, and an init job that bootstraps organizations, teams, repositories, and robot accounts via the Quay API.

## Auth type: decide before first boot

Quay cannot migrate its authentication type after initialization. If you start with Database auth and later try to switch to OIDC, the change will not take effect — this is a hard limitation, not a configuration error.

If you are heading toward Keycloak or any OIDC provider, enable it at first deploy:

```yaml
quayRegistry:
  include: true
  oidc:
    include: true
    provider: "keycloak"
    server: "https://sso.apps.hub.example.com/realms/sso/"
    clientId: "quay"
    clientSecret: "<from-keycloak-client>"
```

This auto-disables `FEATURE_DIRECT_LOGIN` in the config bundle. If you need to reinitialize a registry that started with Database auth, it is cheaper to delete and recreate it fresh with OIDC from the start than to try to layer OIDC onto an existing Database-auth instance.

## Organization structure

Use one Quay org per team or business unit, not one shared org for everything. Orgs are the RBAC boundary — a single sprawling org makes permission review painful. This mirrors the repo's tenancy model (one GitOps instance + namespace per onboarded team).

```yaml
quayRegistry:
  init:
    organizations:
      - name: platform
        email: platform@example.com
      - name: team-alpha
        email: team-alpha@example.com
      - name: team-beta
        email: team-beta@example.com
```

## Teams and permissions

Use teams inside each org rather than assigning permissions to individual users. A team gets a role at the org level (`member`, `creator`, `admin`), and team membership is one place to audit.

Keep org-Admin membership small — most people only need `member` (read/write on repos the team is granted access to).

```yaml
    teams:
      - org: platform
        name: admins
        role: admin
        description: "Platform administrators"
      - org: platform
        name: devs
        role: member
        description: "Platform developers"
      - org: team-alpha
        name: devs
        role: member
        description: "Team Alpha developers"
```

### Directory-backed team sync

If Quay is configured with OIDC (Keycloak) and `FEATURE_TEAM_SYNCING` is enabled, you can bind a team's membership directly to an OIDC group. The init job calls the team sync API automatically when `syncGroup` is set:

```yaml
    teams:
      - org: platform
        name: devs
        role: member
        description: "Platform developers"
        syncGroup: "platform-devs"    # OIDC group name from Keycloak
```

Team syncing is enabled by default in the chart values (`teamSyncing.include: true`). The `syncGroup` value must match the group name in the OIDC groups claim. Once bound, Quay keeps membership current automatically — no need to hand-manage team rosters.

## Robot accounts

Create one robot per automation consumer (CI pipeline, cluster pull secret), not one shared robot for everything. The naming convention is `<org>+<robot>`.

Scope each robot's permissions to the specific repos it needs rather than adding it to an admin team:

```yaml
    robotAccounts:
      - org: platform
        name: cicd
        description: "CI/CD pipeline push/pull"
        permissions:
          - repo: base-images
            role: write
      - org: platform
        name: pull
        description: "Read-only pull access"
        permissions:
          - repo: base-images
            role: read
```

The init job creates the robot, then grants the specified role (`read`, `write`, `admin`) on each repo. Repos must exist first — either pre-created via the `repositories` list or already existing in Quay.

## Pre-creating repositories

The init job can pre-create repos with explicit visibility, ensuring they exist before robot permissions are assigned:

```yaml
    repositories:
      - org: platform
        name: base-images
        visibility: private
        description: "Curated base images"
```

## Repo defaults

Two config settings prevent accidental public exposure:

```yaml
quayRegistry:
  config:
    createPrivateOnPush: true       # repos created via push default to private
    restrictedUsers:
      include: true                 # only superusers + whitelist can create repos/orgs
      whitelist:
        - quayadmin
        - admin
```

- `createPrivateOnPush` ensures that `docker push` to a non-existent repo creates it as private, not public.
- `restrictedUsers` limits who can create repos and orgs — everyone else can only use repos they've been granted access to. This prevents orphaned public repos from pipeline or robot mistakes.

## Init job execution order

The PostSync hook init job runs in dependency order:

1. Wait for Quay health check
2. Create organizations
3. Create teams (with optional team sync binding)
4. Create repositories
5. Create robot accounts (with optional repo-level permissions)

All API calls are idempotent — re-syncing the ArgoCD app re-runs the job safely. The `BeforeHookCreation` delete policy ensures the old Job is cleaned up before each run.

## Keycloak client registration

If using Keycloak OIDC, register Quay as a client in the hub's Keycloak realm:

```yaml
# clusters/mgt/acm-hub/operator-instances.yaml
realm:
  clients:
    quay:
      include: true
      clientSecret: "<same-secret-as-quayRegistry.oidc.clientSecret>"
      redirectUris:
        - "https://registry-quay-quay-enterprise.apps.hub.example.com/oauth2/callback"
      webOrigins:
        - "https://registry-quay-quay-enterprise.apps.hub.example.com"
```

The `clientSecret` must match between the Keycloak client and `quayRegistry.oidc.clientSecret`. The redirect URI follows the pattern `https://<name>-quay-<namespace>.<baseDomain>/oauth2/callback`.
