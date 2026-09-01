#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v ruler >/dev/null 2>&1; then
  if ! command -v npm >/dev/null 2>&1; then
    cat >&2 <<'MSG'
Ruler is not installed, and npm was not found.

Install Node.js/npm, then rerun:
  ./scripts/bootstrap-ai-dev.sh
MSG
    exit 1
  fi

  npm install -g @intellectronica/ruler
fi

ruler apply \
  --agents claude,codex \
  --skills \
  --subagents \
  --no-mcp
