# aap-instance — Handoff

## What it does
Deploys an `AnsibleAutomationPlatform` CR to install AAP components (Controller, Hub, EDA, Lightspeed) with configurable Redis mode.

## Current state
- **Not modified this session** — pre-existing chart
- Disabled by default (`include: false`)
- Not in any active ApplicationSet list (commented out in `cluster-config.yaml`)
- Not tested

## Outstanding
- **Missing dnsName/hostname config** — AAP Controller and Hub typically need route/ingress hostnames; not parameterized
- **No resource requests/limits** — AAP components can be resource-heavy; consider adding sizing controls
- **No storage config** — Controller and Hub need persistent storage for database; not exposed
- **No admin secret** — Initial admin password secret not templated
- **Needs testing** — Deploy on a cluster with the AAP operator installed to validate the CR is accepted

## Testing

**Helm test** (`helm test <release>`): Checks AAP CR exists and controller deployment is available. ArgoCD does not run Helm test hooks — use for local validation only.

**E2E script** (`tests/e2e-test.sh [namespace]`): defaults to `ansible-automation-platform`
- Validates AAP CR phase and controller pods running
- Checks controller route is accessible
- Reports EDA/Hub status if enabled
