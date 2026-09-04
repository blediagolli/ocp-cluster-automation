# prometheus-rules — Handoff

**Date:** 2026-09-04

## What it does
Creates a `PrometheusRule` CR with custom alerting rules across 7 categories: etcd, API server, kubelet, node, PVC, pod, and cluster. Each category is independently toggleable and threshold-configurable via values.

## What was done
- Created new from gap analysis
- **Bug fixed:** float truncation in threshold values (Helm was truncating decimals)
- 7 rule groups with 14 total alerts
- All thresholds configurable per cluster

## Alerts included
- etcd: commit duration, fsync duration, peer RTT
- API server: 5xx error rate, p99 latency
- kubelet: runtime errors, pod startup latency
- node: CPU, memory, disk usage, disk prediction
- PVC: usage threshold
- pod: crash looping, OOMKilled
- cluster: node not ready, clock skew

## Current state
- **Disabled** (`prometheusRules.include: false`) — not enabled on any cluster
- Not tested on cluster

## Outstanding
- Enable per cluster in conf.yaml
- Tune thresholds per environment (prod tighter, dev looser)
- Consider adding recording rules for efficiency
