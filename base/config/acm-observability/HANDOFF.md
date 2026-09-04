# acm-observability — Handoff

## What it does
Deploys ACM MultiClusterObservability with Thanos-based metrics aggregation. Creates: namespace, pull-secret copy, Thanos object storage secret, ObjectBucketClaim (optional via NooBaa), ConsoleLink, and the MultiClusterObservability CR.

## Current state
- **Not modified this session** — pre-existing chart
- Disabled by default (`include: false`)
- Commented out in `cluster-config.yaml` ApplicationSet
- Well-structured with 6 templates covering the full deployment chain
- Supports OBC-backed storage via NooBaa (`objectBucketClaim.include`)

## Outstanding
- **S3 credentials in plaintext** — `accessKey` and `secretKey` are empty strings in values.yaml but would be set in conf.yaml; should use external-secrets or sealed-secrets instead
- **OBC secret wiring gap** — When using OBC, the auto-generated credentials aren't automatically wired into the Thanos secret; the `thanos-secret.yaml` still expects manual `accessKey`/`secretKey` values
- **Missing retention config** — Thanos compaction and retention periods not parameterized
- **No alerting** — No PrometheusRules for observability pipeline health
- **ConsoleLink URL** — Needs to be set per-cluster; no default
- **Needs testing** — Deploy with ODF object storage available to validate end-to-end
