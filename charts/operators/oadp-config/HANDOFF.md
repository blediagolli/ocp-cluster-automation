# oadp-config — Handoff

**Created:** 2026-09-04 (deep dive agents)

## What it does

Deploys a `DataProtectionApplication` CR for OADP (OpenShift API for Data Protection / Velero). Configures:
- Velero server with default plugins (openshift, csi), resource limits, and feature flags
- Node agent (Restic/Kopia) for file-system backups with tolerations and node selectors
- Backup storage locations (S3-compatible)
- Volume snapshot locations

## Current state

- Not enabled on any cluster
- Not in any ApplicationSet `cluster-config.yaml`
- Requires the OADP operator to be installed first (see `base/operators/`)
- `backupLocations` and `snapshotLocations` are empty by default — must be configured per-cluster

## Outstanding

- Enable and configure with actual backup storage credentials per cluster
- Consider adding a `Schedule` CR template for automated cluster backups
