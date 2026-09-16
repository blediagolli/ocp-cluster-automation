# storage-classes — Handoff

**Created:** 2026-09-04 (gap analysis)

## What it does

Deploys custom StorageClass resources. Supports multiple classes with per-class `include` toggle, provisioner, reclaimPolicy, volumeBindingMode, allowVolumeExpansion, and arbitrary parameters.

## Current state

- **Enabled on aws-test** — `fast-ssd` StorageClass (gp3, 6000 IOPS, 250 MB/s throughput, encrypted) via `ebs.csi.aws.com`
- Complements operator-managed `gp2-csi` and `gp3-csi` (default) — does not conflict

## Outstanding

- Default values still use deprecated `kubernetes.io/aws-ebs` in-tree provisioner — per-cluster overrides should use `ebs.csi.aws.com`
- Consider whether ODF-managed StorageClasses make this redundant on some clusters
