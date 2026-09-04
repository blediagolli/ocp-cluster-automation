# gatekeeper-instance — Handoff

## What it does
Deploys an OPA Gatekeeper CR to configure the Gatekeeper admission controller (audit settings, webhook replicas, validating/mutating webhook modes).

## Current state
- **Not modified this session** — pre-existing chart
- Disabled by default (`include: false`)
- Not in any active ApplicationSet list
- Not tested

## Outstanding
- **Template is Gatekeeper CR only** — Named `constraint.yaml` but actually deploys the Gatekeeper operand, not constraints; consider renaming
- **No ConstraintTemplates or Constraints** — The chart only configures the Gatekeeper instance; no sample policies or constraint templates are included
- **No exemptions/exclusions** — Missing namespace exclusion config (important for system namespaces)
- **No resource limits** — Audit and webhook pod resource requests/limits not parameterized
- **Consider Gatekeeper vs Kyverno** — Both `gatekeeper-instance` and `kyverno-instance` charts exist; document which to use when
- **Needs testing** — Deploy with the Gatekeeper operator installed
