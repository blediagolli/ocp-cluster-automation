# openshift-scheduler — Handoff

**Date:** 2026-09-04

## What it does

Manages the cluster `Scheduler` CR (`config.openshift.io/v1`). Configures the kube-scheduler profile (LowNodeUtilization, HighNodeUtilization, NoScoring) and optional custom profiles with plugin configuration.

## What was done

- Created new this session by the deep-dive audit agent
- Single template: `scheduler.yaml` — patches the `cluster` Scheduler CR
- Supports built-in profiles and custom `profileCustomizations` with plugin scoring
- Passes helm lint

## Current state

- **Enabled on aws-test** — `LowNodeUtilization` profile (default), no custom profiles

## Outstanding

- Add to `cluster-config.yaml` ApplicationSet when ready to deploy
- The `profileCustomizations` field structure may vary by OCP version — verify against the target cluster's API schema
