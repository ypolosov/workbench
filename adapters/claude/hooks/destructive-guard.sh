#!/bin/sh
# PreToolUse adapter: the shared guard refuses a shell command with exit 2 and a reason.
# Codex gets an explicit JSON denial: Windows CLI 0.160.1 ran the tool despite exit 2.
# Claude Code and Cursor keep their stderr/exit-2 contract.
set -u

deny() {
  if [ "${WB_AGENT:-}" = codex ]; then
    jq -n --arg reason "$1" '{hookSpecificOutput: {
      hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason
    }}'
    exit 0
  fi
  printf '%s\n' "$1" >&2
  exit 2
}

cmd_text="$(jq -er '(.tool_input.command // .command) | select(type == "string" and length > 0)' 2>/dev/null)" ||
  deny "BLOCKED: не удалось разобрать вход хука или в нём нет команды; блокирую как неопределённо опасный запрос."

reason="$(printf '%s\n' "$cmd_text" | sh "$(dirname "$0")/../../../scripts/guard.sh" 2>&1)"
result=$?
[ "$result" -eq 0 ] || deny "${reason:-BLOCKED: не удалось проверить команду сторожем workbench.}"
exit 0
