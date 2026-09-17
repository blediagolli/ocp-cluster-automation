# Cluster Observability Operator Instance Chart

**Chart:** `charts/operator-instances/cluster-observability/`
**Operator:** cluster-observability-operator (deployed via operator-deployment chart)

## What it does

Manages all Cluster Observability Operator (COO) Custom Resources:

### UIPlugins (cluster-scoped)
Console plugins that add observability features to the OpenShift web console:

- **Dashboards** — observability dashboards console plugin
- **TroubleshootingPanel** — troubleshooting panel console plugin (OCP 4.19+)
- **DistributedTracing** — distributed tracing console plugin (auto-discovers TempoStack)
- **Logging** — logging console plugin (references a LokiStack; supports logsLimit, timeout, schema)
- **Monitoring** — monitoring console plugin with optional ACM proxy, clusterHealthAnalyzer (incident detection), and Perses dashboards

### MonitoringStack (namespace-scoped)
Per-namespace Prometheus + Alertmanager stacks for multi-tenant monitoring. Supports namespace/resource selectors, PVC storage, remote write, tolerations.

### ThanosQuerier (namespace-scoped)
Federated query layer across multiple MonitoringStack instances using Thanos.

## Values structure

```yaml
uiPlugins:
  dashboards:
    include: false
  troubleshootingPanel:
    include: false
  distributedTracing:
    include: false
    timeout: ""
  logging:
    include: false
    lokiStack:
      name: logging-lokistack
    logsLimit: 0
    timeout: ""
    schema: ""
  monitoring:
    include: false
    acm:
      enabled: false
      alertmanager:
        url: ""
      thanosQuerier:
        url: ""
    clusterHealthAnalyzer:
      enabled: false
    perses:
      enabled: false

monitoringStacks: []     # list of MonitoringStack specs with include toggle
thanosQueriers: []       # list of ThanosQuerier specs with include toggle
```

## Dependencies

- `cluster-observability-operator` must be deployed (operator-deployment chart)
- `logging` UIPlugin requires a LokiStack CR (logging-lokistack chart)
- `distributedTracing` UIPlugin requires a TempoStack CR (tempo-instance chart)
- `monitoring` ACM mode requires ACM observability services
- `monitoring` Perses mode installs Perses server automatically

## Testing

- Template tests: `./tests/template-test.sh` — 52 assertions covering all UIPlugin types, MonitoringStack, ThanosQuerier
- E2E tests: `./tests/e2e-test.sh` — 8 checks (operator CSV, CRDs, UIPlugin status, MonitoringStack, console plugins)
- E2E results (2026-09-17): 8/8 pass on hub cluster

## Enabled on

- Hub (acm-hub): dashboards + troubleshootingPanel UIPlugins
- Both UIPlugins: Available=True, registered as console plugins
