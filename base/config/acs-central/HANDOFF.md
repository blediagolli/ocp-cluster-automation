# acs-central — Handoff

**Modified:** 2026-09-04

## What it does
Deploys ACS Central Services (Central, Scanner, ScannerV4, DB) with route/LB/nodePort exposure options. Includes optional init-bundle Job (generates TLS secrets for SecuredCluster), ConsoleLink, and namespace creation.

## What changed this session
- Fixed PVC name collision — Central DB and ScannerV4 DB had separate `claimName` fields but could collide if using defaults. Made claim names explicit: `stackrox-db`, `central-db`, `scanner-v4-db`
- Added telemetry, egress connectivity policy, scanner autoscaling, and monitoring toggles
- Added init-bundle Job mode for same-cluster Central+SecuredCluster setups
- Added ConsoleLink for quick access from OCP console
- **Fixed init-bundle Job empty-secret bug**: Job now checks if sensor-tls has non-empty `ca.pem` data, not just existence. If the secret exists but is empty (e.g., from stale preExisting placeholders), it deletes the stale secrets and regenerates
- Added `delete` verb to init-bundle RBAC Role for stale secret cleanup

## Current state
- **Enabled** on hub (`central.include: true`, `initBundle.include: true`, `consoleLink.include: true`)
- Central v4.11.3 running, all pods healthy
- Init-bundle Job needs to re-run to populate empty TLS secrets (will happen on next ArgoCD sync)

## Gotchas
- Init-bundle Job requires Central to be healthy before it runs — uses a PostSync hook
- The `centralUrl` in consoleLink must match the actual route
- If sensor-tls exists with empty data, the Job now auto-cleans and regenerates (previous behavior was to skip)
