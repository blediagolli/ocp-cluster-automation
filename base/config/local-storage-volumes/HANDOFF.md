# local-storage-volumes — Handoff

## What it does
Deploys a `LocalVolumeSet` CR for the Local Storage Operator. Auto-discovers local NVMe/disk devices on labeled nodes and provisions PVs with a dedicated StorageClass. Primarily used to back ODF/OCS with local disks.

## Current state
- **Not modified this session** — pre-existing chart
- Disabled by default (`localVolumeSet.include: false`)
- Commented out in hub ApplicationSet (`cluster-config.yaml`)
- Not tested

## Outstanding
- Tolerations are hardcoded to `node.ocs.openshift.io/storage` — should be parameterized in values.yaml
- No `maxSize` device filter — could accidentally claim very large devices
- No `maxDeviceCount` limit to cap PVs per node
- Missing `LocalVolume` (explicit device paths) variant — only `LocalVolumeSet` (auto-discovery) is supported
- `nodeSelector.value` defaults to empty string — works for `Exists` operator but review if intentional
- Needs testing with actual local disks on a cluster with the Local Storage Operator installed
