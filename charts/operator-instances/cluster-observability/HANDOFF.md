# Cluster Observability Operator Instance Chart

**Chart:** `charts/operator-instances/cluster-observability/`
**Operator:** cluster-observability-operator (deployed via operator-deployment chart)

## What it does

Creates UIPlugin CRs for the Cluster Observability Operator (COO). UIPlugins register console plugins in OpenShift for observability features:

- **Dashboards** — observability dashboards console plugin
- **TroubleshootingPanel** — troubleshooting panel console plugin
- **DistributedTracing** — distributed tracing console plugin (auto-discovers TempoStack)
- **Logging** — logging console plugin (references a LokiStack)
- **Monitoring** — monitoring console plugin (optional ACM alertmanager/thanos proxy)

UIPlugin CRs are cluster-scoped (no namespace).

## Values structure

```yaml
uiPlugins:
  dashboards:
    include: false
  troubleshootingPanel:
    include: false
  distributedTracing:
    include: false
    timeout: ""              # e.g. "30s" or "5m"
  logging:
    include: false
    lokiStack:
      name: logging-lokistack
  monitoring:
    include: false
    acm:
      enabled: false
      alertmanager:
        url: ""
      thanosQuerier:
        url: ""
```

## Dependencies

- `cluster-observability-operator` must be deployed (operator-deployment chart)
- `logging` UIPlugin requires a LokiStack CR (logging-lokistack chart)
- `distributedTracing` UIPlugin requires a TempoStack CR (tempo-instance chart)
- `monitoring` ACM mode requires ACM observability services

## Testing

- Template tests: `./tests/template-test.sh` — 25 assertions
- E2E tests: `./tests/e2e-test.sh` — validates operator CSV, CRD, UIPlugin resources, conditions, console registration
- Operator CSV: Succeeded on hub
- CRD: `uiplugins.observability.openshift.io` (v1alpha1)

## Enabled on

- Hub (acm-hub): dashboards + troubleshootingPanel
