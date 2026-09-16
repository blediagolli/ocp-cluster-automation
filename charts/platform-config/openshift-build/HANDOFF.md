# openshift-build — Handoff

**Date:** 2026-09-04

## What it does

Manages the cluster `Build` CR (`config.openshift.io/v1`). Configures build defaults: proxy settings (HTTP/HTTPS/git-specific), environment variables (e.g. Maven/NPM mirrors), resource requests/limits, and node placement (nodeSelector + tolerations).

## What was done

- Created new this session by the deep-dive audit agent
- Single template: `build.yaml` — patches the `cluster` Build CR
- Supports separate default proxy and git proxy configurations
- All fields conditional — empty values produce a minimal CR
- Passes helm lint

## Current state

- **Enabled on aws-test** — defaults only (no proxy, no env vars, no resource limits)

## Outstanding

- Add to `cluster-config.yaml` ApplicationSet when ready to deploy
- Useful for air-gapped or proxied environments where builds need mirror URLs and proxy config
