# alertmanager-config — Handoff

**Date:** 2026-09-04

## What it does
Creates the `alertmanager-main` Secret in `openshift-monitoring` containing the full Alertmanager configuration YAML. Supports Slack, PagerDuty, Email, and Webhook receivers with routing, grouping, and inhibit rules.

## What was done
- Created new from gap analysis
- Receiver types: Slack (via api_url_file), PagerDuty (via service_key_file), Email, Webhook
- Routing with matchers, group_by, intervals
- Inhibit rules for severity-based suppression

## Current state
- **Disabled** (`alertmanager.include: false`) — not enabled on any cluster
- Not tested on cluster
- Secrets for Slack URL, PagerDuty key, etc. must exist before enabling

## Outstanding
- Configure receivers per environment in conf.yaml
- Slack/PagerDuty secrets must be pre-created (not managed by this chart)
- Email `authPassword` secret reference is in values but not wired into template — add if needed
- Consider adding `global.smtp_*` settings support
