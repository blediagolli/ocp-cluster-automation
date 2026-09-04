# user-workload-monitoring — Handoff

**Modified:** 2026-09-04 (deep dive agents — was too minimal)

## What it does

Configures user workload monitoring via the `user-workload-monitoring-config` ConfigMap in `openshift-user-workload-monitoring`. Controls:
- Prometheus: retention, replicas, persistent storage, resource limits
- Thanos Ruler: sidecar for recording/alerting rules against object storage
- AlertManager: user-defined alerting
- Remote write: send metrics to external endpoints

## What changed this session

- Expanded from a bare-minimum ConfigMap to full parameterization
- Added Prometheus resources, retention, replicas, storage configuration
- Added Thanos Ruler toggle with resource limits
- Added AlertManager toggle
- Added remote write endpoint support

## Current state

- Not enabled on any cluster (`include: false`)
- Commented out in hub `cluster-config.yaml` ApplicationSet
- Passes helm lint

## Outstanding

- Enable per-cluster and tune retention/storage based on workload volume
- Configure remote write if using external monitoring (e.g., ACM Observability)
