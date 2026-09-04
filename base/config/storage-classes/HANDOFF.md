# storage-classes — Handoff

**Created:** 2026-09-04 (gap analysis)

## What it does

Deploys custom StorageClass resources. Supports multiple classes with per-class `include` toggle, provisioner, reclaimPolicy, volumeBindingMode, allowVolumeExpansion, and arbitrary parameters.

## Current state

- **New chart, not enabled on any cluster**
- Three AWS EBS example classes: fast-ssd (gp3 with IOPS), standard (gp3), archival (sc1 with Retain)
- Provisioner defaults to `kubernetes.io/aws-ebs` — update per infrastructure

## Outstanding

- Replace example provisioners/parameters with actual cluster infrastructure
- Add to `cluster-config.yaml` ApplicationSet when ready
- Consider whether ODF-managed StorageClasses make this redundant on some clusters
