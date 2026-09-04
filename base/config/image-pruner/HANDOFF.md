# image-pruner — Handoff

**Date:** 2026-09-04

## What it does

Manages the `ImagePruner` CR (`imageregistry.operator.openshift.io/v1`). Configures the internal image registry pruner CronJob: schedule, tag retention count, age threshold, job history limits, and resource requests/limits.

## What was done

- Created new this session by the deep-dive audit agent
- Single template: `imagepruner.yaml` — patches the `cluster` ImagePruner CR
- Supports both `keepYoungerThan` (nanoseconds) and `keepYoungerThanDuration` (human-readable) — duration takes precedence
- Passes helm lint

## Current state

- **Not enabled** on any cluster (`include: false`)
- Not listed in any ApplicationSet
- Defaults: daily at midnight, keep 3 tag revisions, keep images younger than 60 minutes

## Outstanding

- Add to `cluster-config.yaml` ApplicationSet when ready to deploy
- Consider enabling on all clusters as a baseline hygiene measure
