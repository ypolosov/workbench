#!/bin/sh
# WP gate reminder (UserPromptSubmit) in the Claude Code hook protocol: Codex uses it as it
# is, and Cursor runs it from the project's Claude Code settings. Adapted from
# FMT-exocortex-template .claude/hooks/wp-gate-reminder.sh (MIT, Tseren Tserenov):
# platform-specific Day Open branch removed, text points to the workbench registry.
# Read-only: returns additionalContext JSON only.

cat >/dev/null
WB_DIR="$(cd "$(dirname "$0")/../../.." && pwd -P)"
# shellcheck source=../../../scripts/paths.sh
. "$WB_DIR/scripts/paths.sh"
# shellcheck source=../../../scripts/hooks.sh
. "$WB_DIR/scripts/hooks.sh"

jq -n --arg ctx "$(wb_wp_reminder)" '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": $ctx}}'
exit 0
