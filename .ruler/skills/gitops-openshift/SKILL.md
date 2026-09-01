# GitOps OpenShift Safety

Use this skill for OpenShift, ACM, Argo CD, Helm, Kustomize, and cluster lifecycle changes.

## Instructions

- Map every change to the controller that reconciles it: Argo CD, ACM, Hive, assisted-service, OLM, or an OpenShift operator.
- Verify cluster inventory fields against the ApplicationSet generator contract.
- Check whether the change affects hub-only resources, spoke clusters, or both.
- Keep hub bootstrap resources under `clusters/mgt/acm-hub/bootstrap/`.
- Keep operator fleet changes under `base/operators/` and `operators/targets/` unless the repo intentionally changes ownership.
- Confirm a safe ordering for provisioning, import, GitOps registration, and day-2 rollout.
- Document live-cluster validation separately from local render validation.
