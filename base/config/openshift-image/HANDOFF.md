# openshift-image — Handoff

**Date:** 2026-09-04

## What it does

Manages the cluster `Image` CR (`config.openshift.io/v1`). Configures image registry policies: allowed/blocked registries, insecure registries, container runtime search registries, and additional trusted CAs for image operations.

## What was done

- Created new this session by the deep-dive audit agent
- Single template: `image.yaml` — patches the `cluster` Image CR
- All registry lists are conditional — empty lists omit the field
- Passes helm lint

## Current state

- **Not enabled** on any cluster (`include: false`)
- Not listed in any ApplicationSet

## Outstanding

- Add to `cluster-config.yaml` ApplicationSet when ready to deploy
- `allowedRegistries` and `blockedRegistries` are mutually exclusive in the OCP API — the template doesn't enforce this, so values must be set correctly
- The `additionalTrustedCA.name` references a ConfigMap in `openshift-config` that must exist separately
