# etcd-defrag — Handoff

**Date:** 2026-09-04

## What it does
CronJob that checks etcd fragmentation on each cluster member and defragments those above a configurable threshold. Processes followers first, then leader. Includes 3 PrometheusRule alerts (job failed, not run recently, high fragmentation).

## What was done this session
- Created from scratch
- Iteratively fixed: image pull (switched to ose-cli), cert paths, nodeSelector (master→control-plane), NetworkPolicy bypass (hostNetwork: true), etcd 3.6 ETCDCTL_ENDPOINTS conflict (env -u), snapshot single-endpoint requirement
- Uses `oc exec` into running etcd pods — no privileged containers, no hostPath mounts, no etcd image dependency

## Current state
- **Enabled** on hub (`clusters/mgt/acm-hub/conf.yaml`)
- **Tested** — 3 members at 11% fragmentation, correctly skipped (threshold 50%)
- In ApplicationSet: `cluster-config.yaml` under hub-only charts

## Gotchas
- `hostNetwork: true` is required — `openshift-etcd` has a default-deny NetworkPolicy
- Must unset `ETCDCTL_ENDPOINTS` env var in all etcdctl calls for etcd 3.6+ compatibility
- `snapshot save` requires exactly one endpoint (split with `cut -d',' -f1`)
