#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AI_WORK_DIR="$ROOT_DIR/.ai-work"
REQUEST_FILE="${AI_REQUEST_FILE:-$AI_WORK_DIR/request.md}"
RESEARCH_FILE="$AI_WORK_DIR/research.md"
PLAN_FILE="$AI_WORK_DIR/plan.md"
IMPLEMENTATION_FILE="$AI_WORK_DIR/implementation.md"
REVIEW_FILE="$AI_WORK_DIR/review.md"
FIX_FILE="$AI_WORK_DIR/fix.md"

ensure_ai_work_dir() {
  mkdir -p "$AI_WORK_DIR"
}

ensure_request_file() {
  ensure_ai_work_dir

  if [ ! -f "$REQUEST_FILE" ]; then
    cp "$AI_WORK_DIR/REQUEST_TEMPLATE.md" "$REQUEST_FILE"
    cat >&2 <<MSG
Created $REQUEST_FILE from the template.
Edit it with your task, then rerun the command.
MSG
    exit 1
  fi
}

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    cat >&2 <<MSG
Required command not found: $command_name
MSG
    exit 1
  fi
}

print_next_file() {
  local label="$1"
  local file="$2"

  printf '\n%s written to %s\n' "$label" "$file"
}
