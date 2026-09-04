# velero-config — Handoff

**Date:** 2026-09-04

## What it does
Configures Velero backup infrastructure: BackupStorageLocation, VolumeSnapshotLocation, and Schedules. Designed for use with OADP operator. Each sub-resource is independently toggleable.

## What was done
- Created new from gap analysis
- Supports AWS/S3-compatible storage with configurable endpoint, path style, region
- Two default schedules: daily (30d retention) and weekly (90d retention)
- Namespace exclusion patterns for openshift-*/kube-*

## Current state
- **Disabled** (`velero.include: false`) — not enabled on any cluster
- Not tested on cluster
- Requires OADP operator installed and `cloud-credentials` secret

## Outstanding
- Configure bucket name and endpoint per cluster
- Pre-create `cloud-credentials` Secret with S3 access keys
- Consider adding GCP/Azure provider support if needed
- Consider adding Restore templates
