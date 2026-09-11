# acm-observability — Handoff

**Modified:** 2026-09-10
**Last tested:** 2026-09-04 on hub (mgt/acm-hub)

## What it does

Deploys ACM MultiClusterObservability with Thanos-based multi-cluster metrics aggregation. Creates:
- Namespace with cluster-monitoring label
- Pull-secret copy (via Sync hook Job from openshift-config)
- ObjectBucketClaim for Thanos storage (NooBaa/ODF)
- Thanos object storage secret (auto-wired from OBC credentials via Sync hook Job)
- MultiClusterObservability CR with retention config
- Optional ConsoleLink for Grafana

## What changed this session

- `consoleLink` → `observabilityConsoleLink`; `href` auto-derived from `cluster.baseDomain`
- `storageClass` uses `cluster.storageClass` from conf.yaml (no longer hardcoded)
- OBC namespace uses `multiClusterObservability.namespace`
- `observabilityNamespace.include` → `multiClusterObservability.createNamespace` (namespace toggle nested under parent key)

## Current state

- **Enabled on hub** — 33+ pods running (Grafana, Thanos stack, AlertManager, metrics-collector, memcached)
- OBC bound on NooBaa, Thanos secret auto-wired from OBC credentials
- Pull secret copied from openshift-config successfully
- Retention: raw 14d, 5m 180d, 1h 365d

## Outstanding

- S3 credentials still in plaintext for manual (non-OBC) mode — use external-secrets if needed
- Verify metrics are flowing from managed clusters via the metrics-collector
