# kyverno-instance — Handoff

## What it does
Deploys a Nirmata EnterpriseKyverno CR with detailed configuration for the Kyverno policy engine (image, liveness probes, metrics, resource filters, networking).

## Current state
- **Not modified this session** — pre-existing chart
- Disabled by default (`include: false`)
- Not in any active ApplicationSet list
- Not tested

## Outstanding
- **Nirmata-specific** — Uses `security.nirmata.io/v1alpha1` API and Nirmata images (`ghcr.io/nirmata/kyverno`); may not match community or Red Hat Kyverno operator
- **Hardcoded image tags** — `v1.8.1-n4kbuild.1` is pinned and likely outdated; parameterize or update
- **No sample policies** — Template is `clusterPolicy.yaml` but only deploys the EnterpriseKyverno CR, not any ClusterPolicy resources
- **Empty fields passed through** — `nodeSelector: {}`, `podAffinity: {}`, `envVars: {}` are hardcoded empty in the template rather than conditionally rendered
- **Consider Gatekeeper vs Kyverno** — Both exist; document when to use which
- **Needs testing** — Requires the Nirmata Kyverno operator; verify API version compatibility
