# Debugging

Use this skill when a render, validation, reconciliation, or cluster workflow fails.

## Instructions

- Reproduce locally with the narrowest command first.
- Separate template/rendering errors from controller/runtime errors.
- Inspect the relevant values file chain before editing chart templates.
- For Argo CD issues, verify ApplicationSet generator input, destination server, project, path, and sync policy.
- For ACM issues, verify `ManagedCluster`, `ManagedClusterSet`, placement, GitOpsCluster, Hive, and assisted-service resources.
- Prefer adding a validation guard or clearer inventory contract when the failure came from ambiguous inputs.

## Evidence To Capture

- Command run
- Failing path/resource
- Expected rendered object
- Actual error or rendered mismatch
- Smallest fix
