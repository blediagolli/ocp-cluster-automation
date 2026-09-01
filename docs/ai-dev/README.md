# AI Development Setup

This repository keeps shared Claude/Codex guidance in `.ruler/`. Ruler can generate native agent files from that source of truth:

- `CLAUDE.md`
- `AGENTS.md`
- `.claude/skills/`
- `.claude/agents/`
- `.codex/skills/`
- `.codex/agents/`

## Bootstrap

The bootstrap installs Ruler with npm if `ruler` is not already available:

```bash
./scripts/bootstrap-ai-dev.sh
```

If you prefer to install it yourself first:

```bash
npm install -g @intellectronica/ruler
```

The script runs:

```bash
ruler apply --agents claude,codex --skills --subagents --no-mcp
```

## Included Skills

- `plan`
- `architecture`
- `implementation`
- `debugging`
- `testing`
- `code-review`
- `security-review`
- `browser-qa`
- `gitops-openshift`

The first eight are the core workflow skills. `gitops-openshift` is the repo-specific layer for OpenShift, ACM, Argo CD, Helm, Kustomize, RBAC, disconnected registry, and cluster lifecycle safety.

## Included Read-Only Agents

- `architect`: challenges plans before changes with provisioning, ApplicationSet, ACM, or lifecycle blast radius.
- `reviewer`: reviews implemented diffs for production risks and avoids invented findings.
- `tester`: identifies local render/lint validation and live-cluster gaps.

## Validation Commands

For this repository, the shared guidance maps the generic placeholders to:

- Test/lint/typecheck/build: `make validate`
- Touched Helm chart: `helm lint <chart>` and `helm template <release> <chart> -f <values...>`
- Touched Kustomize overlay: `oc kustomize <path>`

There is no live-cluster E2E command in this repository. When a change needs one, document the manual ACM, Argo CD, or OpenShift checks separately.

## Optional Workflow Add-Ons

Superpowers and gstack can sit above this repo-local policy layer, but avoid loading several overlapping planning/review systems into the same session unless you intentionally choose which one owns the workflow.

## Claude Research, Codex Implementation

For the default two-agent workflow, write the task once:

```bash
cp .ai-work/REQUEST_TEMPLATE.md .ai-work/request.md
$EDITOR .ai-work/request.md
```

Then run the orchestrated workflow:

```bash
./scripts/ai-run
```

That performs:

1. Claude writes `.ai-work/research.md`.
2. Claude writes `.ai-work/plan.md`.
3. Codex implements the plan and writes `.ai-work/implementation.md`.
4. Claude reviews the working-tree diff and writes `.ai-work/review.md`.

If the review contains actionable findings, run:

```bash
./scripts/ai-fix
```

You can also run each stage manually:

```bash
./scripts/ai-research
./scripts/ai-plan
./scripts/ai-implement
./scripts/ai-review
./scripts/ai-fix
```

Your role is to write the request, approve or adjust the plan when scope matters, and decide whether review findings are real enough to fix. Codex should remain the implementation owner; Claude should remain the research, planning, and independent review voice.

For parallel exploration, use separate worktrees:

```bash
git worktree add ../gitops-feature -b feature/my-change
git worktree add ../gitops-experiment -b experiment/alternative
```

Do not run multiple coding agents against the same working directory at the same time.
