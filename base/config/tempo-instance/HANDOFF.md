# tempo-instance — Handoff

## What it does
Deploys a `TempoStack` instance for distributed tracing. Configures S3 object storage backend with TLS, and exposes a Jaeger-compatible query frontend via an OpenShift Route.

## Current state
- **Not enabled** on any cluster (`include: false`)
- Not in any ApplicationSet element list
- Not tested
- Requires a pre-existing S3 credentials Secret (`tempo-s3-secret`) and CA bundle ConfigMap (`tempo-s3-ca-bundle`)

## Outstanding
- S3 secret and CA bundle names are parameterized but the Secret/ConfigMap themselves must be created externally — consider adding them to the chart or documenting the required format
- No retention/limits configuration (trace retention period, ingestion rate)
- No resource limits on query frontend, distributor, ingester, compactor
- Missing `storageClassName` configuration (only `storageSize` is set)
- No multi-tenancy configuration
- Only S3 storage type supported — add Azure Blob or GCS options
- No OpenTelemetry Collector integration (see `opentelemetry-instance` chart)
