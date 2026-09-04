# openshift-marketplace — Handoff

**Modified:** 2026-09-04 (deep dive agents)

## What it does

Manages local/mirrored CatalogSources for disconnected or air-gapped environments. Templates:
- **Certified operators** — local catalog mirror for Red Hat certified operators
- **Community operators** — local catalog mirror for community operators

Each catalog is configurable with image repository, tag, poll interval, and publisher.

## What changed this session

- Added parameterization for image repository and tag
- Added registry poll interval configuration
- Made cluster registry configurable for disconnected environments

## Current state

- Active on hub and clusters (in ApplicationSet shared config list)
- Both catalogs default to `include: false` — no effect until enabled
- Image tags default to `v4.14` — update to match cluster version when enabling

## Outstanding

- Update `imageTag` defaults to `v4.22` or make dynamic per-cluster
- Configure `cluster.registry` for disconnected environments
- Enable when using mirrored operator catalogs
