# GitOps for Organizations Agent Guidance

This repository defines a GitOps-driven OpenShift fleet pattern using Red Hat Advanced Cluster Management, OpenShift GitOps/Argo CD, Helm charts, Kustomize overlays, ACM policies, and per-cluster inventory under `clusters/` and `conf/`.

## Project Commands

- Dev command: inspect and render the relevant Helm/Kustomize target locally before editing.
- Test command: `make validate`
- Lint command: `make validate`
- Typecheck command: `make validate`
- Build command: `make validate`
- E2E command: no live-cluster E2E is defined in this repository; do not invent one. If a change requires cluster verification, call that out explicitly.

## Default Workflow

1. Inspect the existing manifests, chart values, and docs before proposing changes.
2. Identify the runtime object that a YAML, Helm, or Kustomize edit will render into.
3. Make the smallest coherent change and preserve the existing directory ownership boundaries.
4. Render or validate the touched target before broad validation.
5. Run `make validate` before finalizing when local tools are available.
6. Review the final diff for generated secrets, cluster-scoped blast radius, and drift from the documented inventory contract.

## Repository Boundaries

- `base/provision/openshift-provisioning/` owns cluster provisioning templates.
- `base/config/` owns reusable day-2 configuration charts.
- `base/operators/` owns operator installation and instance rendering.
- `clusters/<environment>/<cluster>/` owns cluster inventory, provisioning values, overlays, and hub bootstrap content.
- `clusters/mgt/acm-hub/applicationsets/` owns Argo CD ApplicationSet fan-out.
- `docs/` and `README.md` must stay aligned with any workflow or inventory contract changes.

## GitOps Safety Rules

- Never commit real credentials, pull-secret data, SSH private keys, kubeconfigs, or provider tokens.
- Treat rendered `Secret` objects as examples only unless the secret workflow is explicitly protected outside Git.
- Be careful with cluster-scoped resources such as `ClusterRoleBinding`, `ManagedCluster`, `ManagedClusterSetBinding`, `Subscription`, CRDs, and ACM policies.
- Prefer explicit cluster/profile targeting over broad selectors.
- Do not silently switch Argo CD destinations. Remote spoke clusters need their registered server address, not `https://kubernetes.default.svc`.
- Keep OpenShift version assumptions visible in paths, values, or docs.

## Independent Review Pattern

Use a second model or subagent when the change alters provisioning, RBAC/security posture, ApplicationSet selection, operator channels, cluster registration, or documented production workflows. Give the reviewer the diff and files, not the full implementation rationale, so it can challenge assumptions independently.

## Claude/Codex Handoff

The default multi-agent flow is:

1. Claude researches the request and writes `.ai-work/research.md`.
2. Claude turns that research into `.ai-work/plan.md`.
3. Codex implements from the request, research, and plan.
4. Claude reviews the final working-tree diff and writes `.ai-work/review.md`.
5. Codex fixes only substantiated, actionable review findings.

Use the scripts in `scripts/ai-*` for this flow. Codex is the implementation owner; Claude is the research, planning, and independent review voice.

## Tooling Policy

Start with repository-local validation. Add external MCPs, browser automation, live cluster access, or service integrations only when the work repeatedly requires that external context.

For parallel work, use separate git worktrees:

```bash
git worktree add ../gitops-feature -b feature/my-change
git worktree add ../gitops-experiment -b experiment/alternative
```

Do not have multiple coding agents edit the same working directory at the same time.
