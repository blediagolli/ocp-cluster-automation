# openshift-image-registry — Handoff

## What it does
Configures the internal OpenShift image registry via the `Config` CR (`imageregistry.operator.openshift.io/v1`). Sets replicas, management state, rollout strategy, and PVC-based storage.

## Current state
- **Not enabled** — commented out in hub ApplicationSet, `include: false` in defaults
- **Not tested** this session
- Pre-existing chart, not modified this session

## Outstanding
- **PVC-only storage** — only `pvc` type is implemented; no support for S3, GCS, Azure blob, Swift, or emptyDir
- **Missing fields**: `httpSecret`, `proxy`, `requests/limits`, `nodeSelector`, `tolerations`, `topologySpreadConstraints`, `routes` (for external access)
- **No `spec.defaultRoute`** — common requirement to expose the registry externally
- **No image pruner coordination** — the separate `image-pruner` chart exists but they share no values
- Add S3/OBC storage option (similar to etcd-backup) and route exposure before enabling
