# volume-snapshot-classes — Handoff

**Created:** 2026-09-04 (gap analysis)

## What it does

Deploys VolumeSnapshotClass resources for CSI snapshot support. Supports multiple drivers (Ceph RBD, CephFS, AWS EBS, vSphere) with per-class `include` toggles, deletionPolicy, and parameters.

## Current state

- **New chart, not enabled on any cluster**
- Four example classes defined (all disabled by default)
- Parameters left empty — need cluster-specific values (e.g. clusterID, snapshotter secret)

## Outstanding

- Enable on clusters with ODF/CSI and populate driver-specific parameters
- Add to `cluster-config.yaml` ApplicationSet when ready
- Ceph classes may need snapshotter secret name/namespace in parameters
