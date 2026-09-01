# Testing

Use this skill to validate manifest and documentation changes.

## Local Validation

- Run `make validate` for broad repository validation.
- Use `helm lint <chart>` for touched Helm charts.
- Use `helm template <release> <chart> -f <values...>` for rendered output inspection.
- Use `oc kustomize <path>` for touched Kustomize overlays.
- If `oc` is unavailable, use `kubectl kustomize` only when the target does not depend on OpenShift-specific `oc kustomize` behavior.

## Review Focus

- Confirm every changed template renders with the sample values that exercise it.
- Confirm ApplicationSet paths still point to existing directories.
- Confirm operator channels, install plans, and target namespaces match the profile contract.
- Confirm docs and examples match actual filenames and fields.

## Reporting

Report validation commands run and any commands skipped because tooling or live cluster access was unavailable.
