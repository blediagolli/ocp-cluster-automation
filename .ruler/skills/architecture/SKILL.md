# Architecture

Use this skill to challenge a plan or design before implementation.

## Instructions

- Review whether the change belongs in provisioning, hub bootstrap, operator management, day-2 config, cluster inventory, or documentation.
- Check that Git remains the source of truth and that reconciliation ownership is clear.
- Look for cross-cluster blast radius from selectors, default values, ApplicationSet generators, policies, and chart templates.
- Prefer explicit contracts over hidden conventions.
- Consider lifecycle order: hub bootstrap, ACM registration, Argo CD destination registration, provisioning, import, day-2 configuration, and operator installation.
- Recommend the smallest design that preserves future OpenShift version/profile evolution.

## Challenge Questions

- What cluster set, role, environment, or profile receives this change?
- What renders the final resource, and what controller reconciles it?
- How is rollback handled?
- What validation proves the generated manifests still match intent?
