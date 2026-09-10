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
