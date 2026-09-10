# openshift-dns — Handoff

## What it does
Configures the cluster `DNS` operator CR (`operator.openshift.io/v1`). Currently only sets `nodePlacement.tolerations` to `Exists` (tolerate all taints) so CoreDNS pods can run on any node.

## Current state
- **Not enabled** — commented out in hub ApplicationSet, `include: false` in defaults
- **Not tested** this session
- Pre-existing chart, not modified this session

## Outstanding
- **Very minimal** — only configures tolerations, nothing else
- **Missing**: upstream DNS forwarders (`spec.servers[].forwardPlugin`), per-zone forwarding, node selector, log level, cache TTL overrides
- **`tolerateAll` flag is unused** — the template hardcodes `operator: Exists` regardless of the value; the conditional should gate the toleration
- **No `spec.servers` support** — custom DNS forwarding zones are a common day-2 requirement
- Parameterize toleration list and add upstream resolver configuration before enabling
