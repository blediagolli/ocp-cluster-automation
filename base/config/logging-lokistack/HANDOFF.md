# logging-lokistack — Handoff

**Date:** 2026-09-04

## What it does
Deploys LokiStack for OpenShift log aggregation with configurable storage backend (S3/Azure/GCS/Swift), size presets, and rate limits. Includes ClusterLogForwarder for routing infrastructure, application, and audit logs. Creates RBAC for log access.

## What was done this session
- Fixed hardcoded storage type — was always `s3`, now uses `storageSecretType` value
- Added configurable ingestion rate, burst size, and query timeout
- Added `storageSize` annotation parameter
- Made storage class name configurable (was hardcoded)
- Added `collectAuditLogs` toggle for ClusterLogForwarder

## Current state
- **Disabled** by default (`include: false`)
- Commented out in ApplicationSet — uncomment `template: logging-lokistack` to enable
- Requires a pre-existing secret (`logging-loki-odf`) with S3/storage credentials

## Gotchas
- The `size` field (`1x.extra-small`, `1x.small`, etc.) determines actual PVC sizes — `storageSize` is only an annotation
- Secret must exist before LokiStack CR is created or it will fail to reconcile
- RBAC template grants log reading to cluster-admins — adjust if using custom groups
