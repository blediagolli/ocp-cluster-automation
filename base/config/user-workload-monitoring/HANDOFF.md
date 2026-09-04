# user-workload-monitoring — Handoff

**Modified:** 2026-09-04
**Last tested:** 2026-09-04 on hub (mgt/acm-hub)

## What it does

Enables user workload monitoring via two ConfigMaps:
- `cluster-monitoring-config` in `openshift-monitoring` — sets `enableUserWorkload: true`
- `user-workload-monitoring-config` in `openshift-user-workload-monitoring` — configures Prometheus retention, storage, resources, Thanos Ruler, AlertManager, and remote write

## What changed this session

- Expanded from a bare-minimum ConfigMap to full parameterization
- Added Prometheus resources, retention, persistent storage toggle
- Added Thanos Ruler, AlertManager, and remote write toggles
- Removed invalid `prometheus.replicas` field — rejected by the `monitoringconfigmaps.openshift.io` admission webhook
- Configured hub with 48h retention, 50Gi persistent storage on ODF ceph-rbd, production resource limits

## Current state

- **Enabled on hub** with persistent storage (2x 50Gi PVCs on `ocs-external-storagecluster-ceph-rbd`)
- Hub: 48h retention, 2 CPU / 6Gi memory limits
- Active in ApplicationSet (shared config — applies to all clusters)
- Synced and Healthy on both hub and prod
- All 5 pods running: prometheus-operator, 2x prometheus-user-workload, 2x thanos-ruler

## Outstanding

- ACM Observability not deployed — remote write has no target currently
- Prod cluster is synced but using defaults (ephemeral storage) — configure per-cluster values when needed
