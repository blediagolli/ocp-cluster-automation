# opentelemetry-instance — Handoff

## What it does
Deploys an `OpenTelemetryCollector` CR. Configured as a deployment-mode collector that receives OTLP traces (gRPC + HTTP) and exports them to a Tempo distributor endpoint.

## Current state
- **Not enabled** — not in any ApplicationSet, `include: false` in defaults
- **Not tested** this session
- Pre-existing chart, not modified this session

## Outstanding
- **Traces only** — no metrics or logs pipelines configured; only a traces pipeline with OTLP receiver → OTLP exporter
- **Hardcoded Tempo endpoint** — `tempo-servicemesh-distributor.tracing-system.svc.cluster.local:4317` is baked into values; should work with any OTLP backend
- **TLS insecure** — `tls.insecure: true` is hardcoded on the exporter; should be configurable for production
- **No processors** — missing batch, memory_limiter, resource, span processors that are standard in production collectors
- **No `config` block flexibility** — the template renders each config field individually rather than using `toYaml` on the whole config block, making it hard to add arbitrary processors/extensions
- **Missing**: resource limits, replicas, autoscaling, service monitor for self-monitoring
- Consider restructuring to render `spec.config` as a single YAML block for flexibility
