# machine-health-checks — Handoff

**Created:** 2026-09-04 (gap analysis)

## What it does

Deploys MachineHealthCheck resources in `openshift-machine-api` to auto-remediate unhealthy nodes. Iterates over a configurable list of checks, each with its own selector, unhealthy conditions, timeout thresholds, and maxUnhealthy percentage.

## Current state

- **New chart, not enabled on any cluster**
- Defaults: worker healthcheck (Ready=False/Unknown for 5m, maxUnhealthy 40%) and infra healthcheck (disabled)
- Not yet added to any ApplicationSet

## Outstanding

- Enable on a cluster and test that MachineHealthChecks are created correctly
- Add to `cluster-config.yaml` ApplicationSet when ready
- Tune timeouts and maxUnhealthy per environment
