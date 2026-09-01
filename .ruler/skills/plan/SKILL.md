# Plan

Use this skill before non-trivial changes to manifests, charts, ApplicationSets, policies, or documentation contracts.

## Instructions

- Summarize the requested outcome in repository terms: provisioning, hub bootstrap, day-2 config, operators, docs, or validation.
- Identify affected paths and the rendered Kubernetes/OpenShift resources.
- Check current behavior before editing. Prefer `helm template`, `helm lint`, `oc kustomize`, and `make validate` where they apply.
- Call out assumptions about OpenShift version, cluster role, operator profile, environment, and live-cluster availability.
- Split work into small changes that can be rendered or reviewed independently.
- Ask for clarification only when a wrong assumption could alter production cluster behavior.

## Output Shape

- Goal
- Affected paths
- Validation plan
- Risks or assumptions
