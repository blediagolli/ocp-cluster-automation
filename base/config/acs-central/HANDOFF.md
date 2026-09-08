# acs-central — Handoff

**Modified:** 2026-09-08

## What it does
Deploys ACS Central Services (Central, Scanner, ScannerV4, DB) with route/LB/nodePort exposure options. Includes optional init-bundle Job (generates TLS secrets for SecuredCluster), ConsoleLink, namespace creation, and ACM Policy for distributing Central credentials to managed clusters.

## What changed this session
- Fixed init-bundle Job empty-secret bug: checks for non-empty `ca.pem` data, deletes stale empty secrets
- Fixed password lookup: switched from go-template `base64decode` to jsonpath + `base64 -d`
- Added `delete` verb to init-bundle RBAC Role for stale secret cleanup
- Added `distributeAuth` option: creates an ACM Policy that distributes `central-auth` secret (Central admin password) to managed clusters via hub-templates. Targets clusters by environment label.

## Current state
- **Enabled** on hub with init-bundle and credential distribution
- Central v4.11.3 running, all pods healthy
- ACM Policy distributes `central-auth` to dev/prod clusters

## Gotchas
- Init-bundle Job requires Central to be healthy — uses a PostSync hook
- The `centralUrl` in consoleLink must match the actual route
- `distributeAuth` uses ACM hub-templates to read `central-htpasswd` secret — if the secret name changes, update the Policy template
- `targetEnvironments` controls which clusters receive the credential (default: dev, prod)
