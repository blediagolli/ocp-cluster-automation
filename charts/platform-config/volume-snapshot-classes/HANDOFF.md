# volume-snapshot-classes — Handoff

**Created:** 2026-09-04 (gap analysis)

## What it does

Deploys VolumeSnapshotClass resources for CSI snapshot support. Supports multiple drivers (Ceph RBD, CephFS, AWS EBS, vSphere) with per-class `include` toggles, deletionPolicy, and parameters.

## Current state

- **Enabled on aws-test** — `csi-aws-ebs-snapclass` for EBS CSI snapshots
- Four example classes defined in defaults (all disabled) — enable per infrastructure

## Outstanding

- Ceph classes need snapshotter secret name/namespace in parameters for ODF clusters
