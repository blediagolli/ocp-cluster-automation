# global-pull-secrets — Handoff

**Created:** 2026-09-04 (gap analysis)
**Bug fixed:** Template syntax error corrected during deep dive audit

## What it does

Manages pull secrets at two levels:
- **Namespace pull secrets** — Creates dockerconfigjson Secrets in specified namespaces
- **Global pull secret** — Patches the cluster-wide pull secret in `openshift-config`

## Current state

- **New chart, not enabled on any cluster**
- Template syntax bug was fixed (agent deep dive)
- All entries disabled by default with placeholder credentials

## Outstanding

- **Do not commit real credentials** — use SealedSecrets or ExternalSecrets instead
- Add to `cluster-config.yaml` ApplicationSet when ready
- Consider integrating with external-secrets-operator (already deployed) for credential management
