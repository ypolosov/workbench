#!/bin/sh
# Close gate reminder (UserPromptSubmit) in the Claude Code hook protocol: Codex uses it as
# it is, and Cursor runs it from the project's Claude Code settings. Adapted from
# FMT-exocortex-template .claude/hooks/close-gate-reminder.sh (MIT, Tseren Tserenov):
# points to the close-session skill of this project instead of /run-protocol.
# Read-only: returns additionalContext JSON only.

INPUT=$(cat)
WB_DIR="$(cd "$(dirname "$0")/../../.." && pwd -P)"
# shellcheck source=../../../scripts/paths.sh
. "$WB_DIR/scripts/paths.sh"
# shellcheck source=../../../scripts/hooks.sh
. "$WB_DIR/scripts/hooks.sh"

# Multiline prompts carry literal control chars that break jq; flatten them first.
SANITIZED=$(printf '%s' "$INPUT" | LC_ALL=C tr '\n\r\t' '   ')
PROMPT=$(printf '%s' "$SANITIZED" | jq -r '.prompt // empty')

CTX="$(wb_close_reminder "$PROMPT")"
if [ -n "$CTX" ]; then
  jq -n --arg ctx "$CTX" '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": $ctx}}'
else
  echo '{}'
fi
exit 0
