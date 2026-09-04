# odf-storagecluster — Handoff

## What it does
Deploys an ODF `StorageCluster` CR with configurable device sets, encryption, and resource profile. Includes an optional `ConfigMap` for CSI driver tolerations (rook-ceph-operator-config) to allow Ceph CSI pods on control-plane nodes.

## Current state
- **Not enabled** — commented out in hub ApplicationSet, `include: false` in defaults
- **Not tested** this session
- Pre-existing chart, not modified this session (values were touched for minor cleanup)

## Outstanding
- **No external storage mode** — template assumes internal OCS device sets only; no support for `externalStorage` or connecting to an external Ceph cluster (the hub currently uses `ocs-external-storagecluster`)
- **Hardcoded device set name** — always `ocs-deviceset`, should be parameterized if multiple sets are needed
- **No node affinity / tolerations on StorageCluster** — only CSI tolerations are configurable, not the OSD pod placement
- **No NFS or CephFS pool configuration** — only RBD block storage is implied
- **Missing multiCloudGateway options** — `reconcileStrategy: manage` is hardcoded, no NooBaa-specific settings exposed
- Test deployment against the hub's external storage setup before enabling
