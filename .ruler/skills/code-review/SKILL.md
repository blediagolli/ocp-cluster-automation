# Code Review

Use this skill for production-focused review of diffs.

## Findings Standard

Only report a finding when it has:

- Severity
- Exact file and line
- Failure scenario
- Why existing validation would miss it
- Smallest credible fix

## Review Priorities

- Broken Helm rendering or invalid values paths
- Kustomize paths that no longer exist
- ApplicationSet selectors or destinations that target the wrong clusters
- Cluster-scoped resources added without clear ownership
- Drift between README/docs and repository behavior
- Changes that make rollback or cluster lifecycle ordering unsafe

Do not generate issues merely to look useful. Say clearly when no actionable findings are found.
