# Implementation

Use this skill while making repository changes.

## Instructions

- Preserve the existing Helm, Kustomize, and directory patterns.
- Keep values in `conf/` and cluster inventory in `clusters/` consistent.
- Avoid broad refactors unless the requested change depends on them.
- Prefer templated chart changes when the behavior must apply across clusters; prefer cluster-local values or overlays when only one cluster should change.
- Keep generated outputs out of the source tree unless the repository already tracks that class of generated artifact.
- Update docs when a user-facing workflow, inventory contract, validation command, or secret-handling assumption changes.

## Kubernetes/OpenShift Checks

- Confirm names, namespaces, labels, selectors, and API groups match the target CRDs.
- Check whether a resource is cluster-scoped or namespace-scoped before moving it.
- Keep RBAC bindings narrow and explain unavoidable cluster-wide privileges.
- Do not introduce plaintext production secret material.
