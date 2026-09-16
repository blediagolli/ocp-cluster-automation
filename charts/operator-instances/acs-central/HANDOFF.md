# acs-central — Handoff

**Modified:** 2026-09-15

## What it does
Deploys ACS Central Services (Central, Scanner, ScannerV4, DB) with route/LB/nodePort exposure options. Includes optional init-bundle Job (generates TLS secrets for SecuredCluster), ConsoleLink, namespace creation, ACM Policy for distributing Central credentials to managed clusters, optional OIDC authentication via Keycloak, trusted CA bundle injection, and custom TLS via Vault + ESO.

## What changed this session
- Added `defaultTLS` — ExternalSecret pulls wildcard cert from Vault (`secret/data/openshift/wildcard-cert`) into `central-default-tls-cert` Secret; Central CR references it via `spec.central.defaultTLSSecret` so the route serves the cluster's trusted wildcard cert
- Added `trustedCA` — ConfigMap with `config.openshift.io/inject-trusted-cabundle: "true"` label for OpenShift cluster-wide CA injection

## Current state
- **Enabled** on hub with init-bundle, credential distribution, OIDC, trusted CA, and wildcard TLS
- Central running, all pods healthy, route serving trusted wildcard cert
- ACM Policy distributes `central-auth` to dev/prod clusters
- OIDC auth provider configured for Keycloak SSO realm

## Gotchas
- Init-bundle Job requires Central to be healthy — uses a PostSync hook
- `centralUrl` is auto-derived from `cluster.baseDomain` — override in operator-instances.yaml only if the route hostname differs
- `distributeAuth` uses ACM hub-templates to read `central-htpasswd` secret — if the secret name changes, update the Policy template
- `targetEnvironments` controls which clusters receive the credential (default: dev, prod)
- OIDC issuer defaults to `https://sso.<baseDomain>/realms/<realm>` — override `oidc.issuer` if Keycloak uses a different route
- `oidc.clientSecret` must match in both the ACS auth provider Secret and the KeycloakRealmImport client
- KeycloakRealmImport uses partial realm import — it creates/updates the client but doesn't delete other clients in the realm
- `defaultTLS` requires the wildcard cert to exist in Vault at the configured path — if Vault is reinitialized, the cert must be re-stored
- `trustedCA` ConfigMap must not conflict with an existing one of the same name in the namespace

## Testing

**Helm test** (`helm test <release>`): Checks Central CR has Deployed=True condition. ArgoCD does not run Helm test hooks — use for local validation only.

**E2E script** (`tests/e2e-test.sh [namespace]`): defaults to `stackrox`
- Validates Central CR status, pods running, and route accessible via `/v1/ping`
- Checks init-bundle job completed and scanner pods running
- Reports 5-step pass/fail summary
