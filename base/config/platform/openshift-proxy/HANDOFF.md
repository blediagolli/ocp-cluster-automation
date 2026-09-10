# openshift-proxy — Handoff

**Date:** 2026-09-04

## What it does

Manages the cluster `Proxy` CR (`config.openshift.io/v1`). Configures cluster-wide HTTP/HTTPS proxy settings, no-proxy exclusions, and a trusted CA bundle for proxy TLS inspection.

## What was done

- Created new this session by the deep-dive audit agent
- Single template: `proxy.yaml` — patches the `cluster` Proxy CR
- All fields conditional — only set when values are non-empty
- Passes helm lint

## Current state

- **Not enabled** on any cluster (`include: false`)
- Not listed in any ApplicationSet

## Outstanding

- Add to `cluster-config.yaml` ApplicationSet when ready to deploy
- The `trustedCA.name` references a ConfigMap in `openshift-config` — that ConfigMap must be created separately (not managed by this chart)
