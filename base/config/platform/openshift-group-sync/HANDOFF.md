# openshift-group-sync — Handoff

**Date:** 2026-09-04

## What it does
CronJob that runs `oc adm groups sync` to synchronize LDAP groups into OpenShift Group objects. Creates a ServiceAccount (cluster-admin), ConfigMap with LDAPSyncConfig, and the CronJob itself. Supports RFC2307 schema with configurable group/user base DNs, filters, and attribute mappings.

## What was done
- Created new from gap analysis
- Full RFC2307 LDAP sync support
- Mounts bind password from Secret, CA cert from ConfigMap
- CA mount conditionally skipped when `insecure: true`

## Current state
- **Disabled** (`groupSync.include: false`) — not enabled on any cluster
- Not tested — requires LDAP server to test against
- Uses `cluster-admin` ClusterRoleBinding (could be scoped down)

## Outstanding
- Needs LDAP connection details per cluster in conf.yaml
- Prerequisite: Secret for bind password, ConfigMap for CA cert
- `groupMappings` value exists but isn't used in the template — add whitelist/mapping support if needed
- Consider scoping RBAC to just `groups` resource instead of `cluster-admin`
