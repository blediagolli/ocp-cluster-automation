# etcd-backup — Handoff

**Date:** 2026-09-04
**Last commit:** 819792c

---

## Current state

- Chart supports two storage backends: `pvc` and `obc` (ObjectBucketClaim via NooBaa/ODF)
- Hub cluster is configured for `obc` mode in `clusters/mgt/acm-hub/conf.yaml`
- OBC is provisioned and bound: bucket `etcd-backup-2bb0ab3e-...` on NooBaa
- PVC mode was tested end-to-end and works — snapshot taken, copied, stored
- OBC mode: snapshot + copy works, but **S3 upload not yet verified** — cluster API timed out before logs could be checked

## Must verify

1. **Check the last test job** — `etcd-backup-obc-v3` was created but never confirmed:
   ```
   oc get pod -n openshift-etcd -l job-name=etcd-backup-obc-v3
   oc logs -n openshift-etcd -l job-name=etcd-backup-obc-v3
   ```

2. **If it failed**, likely cause is the Python S3v4 signing in `s3upload.py` (embedded in the `etcd-backup-script` ConfigMap). Check that `hmac.new()` works in the ose-cli Python version — it may need `hmac.HMAC()` instead. To debug interactively:
   ```
   oc create job --from=cronjob/etcd-backup etcd-backup-test -n openshift-etcd
   oc logs -f -n openshift-etcd -l job-name=etcd-backup-test
   ```

3. **Retention** — The `--retention` flag in s3upload.py lists bucket prefixes and deletes old ones. Not yet tested with enough backups to trigger cleanup.

## Key patterns

- **`hostNetwork: true`** — Required because `openshift-etcd` namespace has a `default-deny` NetworkPolicy. Without it the pod can't reach the API server.
- **`env -u ETCDCTL_ENDPOINTS`** — etcd 3.6 (OCP 4.22) raises a fatal error when the env var conflicts with `--endpoints`/`--cluster` CLI flags. All `etcdctl` calls unset it.
- **`snapshot save` needs a single endpoint** — `ETCDCTL_ENDPOINTS` contains all members comma-separated. Script extracts the first one with `cut -d',' -f1`.
- **OBC auto-resources** — An `ObjectBucketClaim` creates a Secret (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) and ConfigMap (BUCKET_NAME, BUCKET_HOST, BUCKET_PORT) with the same name as the OBC. No manual credential management needed.

## Nice to have

- Add PrometheusRule alerts (EtcdBackupJobFailed, EtcdBackupNotRunRecently) — the etcd-defrag chart has these as a reference pattern
- Add `etcdctl snapshot status` verification after upload for integrity checking
- Test switching back to PVC mode (just set `storage.type: pvc` in conf.yaml)

## Testing

**Helm test** (`helm test <release>`): Checks CronJob, ServiceAccount, and ConfigMap exist in openshift-etcd. ArgoCD does not run Helm test hooks — use for local validation only.

**E2E script** (`tests/e2e-test.sh`):
- Validates CronJob schedule and RBAC (ServiceAccount, ClusterRoleBinding)
- Checks last Job completion status
- Verifies storage binding (PVC or OBC depending on mode)
