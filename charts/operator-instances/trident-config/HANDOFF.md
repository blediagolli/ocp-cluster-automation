# trident-config — Handoff

## What it does
Deploys NetApp Trident storage orchestrator via `TridentOrchestrator` CR and an optional `VolumeSnapshotClass` for Trident CSI snapshots.

## Current state
- **Not enabled** on any cluster (`include: false`)
- Not in any ApplicationSet element list
- Not tested

## Outstanding
- No `TridentBackendConfig` resources — Trident needs at least one backend (ONTAP, SolidFire, etc.) to provision storage
- No `StorageClass` definitions for Trident-backed storage (NFS, iSCSI, etc.)
- VolumeSnapshotClass driver is hardcoded to `csi.trident.netapp.io` — already correct but should confirm against the installed CSI driver
- `debug: true` is the default — should be `false` for production
- IPv6 is hardcoded to `false` — parameterize if dual-stack is needed
- `silenceAutosupport: false` sends telemetry to NetApp — document or make configurable
- No node selector or tolerations for the Trident controller pod
