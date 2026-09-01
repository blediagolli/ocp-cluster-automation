# AI Work Handoff

This directory is the handoff surface between Claude Code and Codex.

Tracked files:

- `REQUEST_TEMPLATE.md`: copy this to `.ai-work/request.md` for a new task.

Ignored local files:

- `request.md`: your task request.
- `research.md`: Claude's repo research.
- `plan.md`: Claude's implementation plan for Codex.
- `implementation.md`: Codex's implementation report.
- `review.md`: Claude's independent final review.
- `fix.md`: Codex's fix report after review findings.

Typical use:

```bash
cp .ai-work/REQUEST_TEMPLATE.md .ai-work/request.md
$EDITOR .ai-work/request.md
./scripts/ai-run
```
