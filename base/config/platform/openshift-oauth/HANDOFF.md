# openshift-oauth — Handoff

**Date:** 2026-09-04

## What it does
Manages the cluster-wide `OAuth` CR (`config.openshift.io/v1`). Configures identity providers (LDAP, OIDC, GitHub, HTPasswd) and token settings via values.

## What was done
- Created new from gap analysis
- Supports 4 provider types with full attribute mapping
- Token max age configurable per cluster

## Current state
- **Disabled** (`oauth.include: false`) — not enabled on any cluster
- Not tested on cluster
- Prerequisite secrets (LDAP bind, OIDC client, etc.) must exist before enabling

## Outstanding
- Needs real identity provider config per cluster in conf.yaml
- No Google/GitLab provider templates yet (add as needed)
- Consider adding `templates` field support for custom login pages
