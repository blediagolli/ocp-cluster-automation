# openshift-image-registry — Handoff

**Date:** 2026-09-16

## What it does
Configures the internal OpenShift image registry via the `Config` CR (`imageregistry.operator.openshift.io/v1`). Sets replicas, management state, rollout strategy, default route, and storage.

## What was done
- Added S3 storage support (bucket, region, encrypt, keyID, regionEndpoint, virtualHostedStyle)
- Added emptyDir storage support (for non-production/testing)
- Added `defaultRoute` toggle for external registry access
- Deployed to aws-test with S3 storage matching the installer-provisioned bucket

## Current state
- **Enabled on aws-test** — S3 storage, 2 replicas, Managed
- Supports storage types: `pvc`, `s3`, `emptyDir`

## Outstanding
- Missing fields: `httpSecret`, `proxy`, `resources`, `nodeSelector`, `tolerations`, `topologySpreadConstraints`
- GCS, Azure blob, and Swift storage types not implemented
- No image pruner coordination — the separate `image-pruner` chart exists but they share no values
