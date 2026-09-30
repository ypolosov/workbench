#!/bin/sh
# SessionStart hook in the Claude Code hook protocol: Codex uses it as it is, and Cursor
# runs it from the project's Claude Code settings. Gives the agent the session context of
# scripts/hooks.sh. Read-only; never fails the session.
set -u

WB_DIR="$(cd "$(dirname "$0")/../../.." && pwd -P)"
# shellcheck source=../../../scripts/paths.sh
. "$WB_DIR/scripts/paths.sh"
# shellcheck source=../../../scripts/hooks.sh
. "$WB_DIR/scripts/hooks.sh"

input="$(cat 2>/dev/null || true)"
# Claude Code and Codex name the session folder cwd; Cursor names its workspace roots.
cwd="$(printf '%s' "$input" | jq -r '.cwd // .workspace_roots[0]? // empty' 2>/dev/null)"
cwd="${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}"

ctx="$(wb_session_context "$(wb_agent "$input")" "$cwd")"
jq -n --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
