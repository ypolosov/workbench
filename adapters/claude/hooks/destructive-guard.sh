#!/bin/sh
# PreToolUse hook on shell commands, in the Claude Code hook protocol: Codex uses it as it
# is, and Cursor runs it from the project's Claude Code settings. It takes the command out
# of the hook input (tool_input.command; Cursor's own format has command) and hands it to
# the guard's core, scripts/guard.sh: exit 2 with the reason on stderr refuses it.
set -u

cmd_text="$(jq -er '(.tool_input.command // .command) | select(type == "string" and length > 0)' 2>/dev/null)" || {
  echo "BLOCKED: не удалось разобрать вход хука или в нём нет команды; блокирую как неопределённо опасный запрос." >&2
  exit 2
}
printf '%s\n' "$cmd_text" | sh "$(dirname "$0")/../../../scripts/guard.sh"
