# image-mirror-config — Handoff

**Created:** 2026-09-04 (gap analysis)

## What it does

Deploys ImageDigestMirrorSet resources to configure registry mirroring at the cluster level. Each source registry maps to one or more mirror registries with per-entry `include` toggle.

## Current state

- **New chart, not enabled on any cluster**
- Three example mirrors: registry.redhat.io, quay.io, docker.io → `mirror.example.com/*`
- Uses ImageDigestMirrorSet (digest-based, OCP 4.13+)

## Outstanding

- Replace `mirror.example.com` with actual internal registry
- Decide whether to use ImageDigestMirrorSet (digest only) or ImageTagMirrorSet (tag-based)
- Add to `cluster-config.yaml` ApplicationSet when ready
