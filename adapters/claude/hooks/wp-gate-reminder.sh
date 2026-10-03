#!/bin/sh
# UserPromptSubmit hook in Claude Code's protocol; Codex takes it as it is, and Cursor runs
# it from the project's Claude Code settings. On every message of the owner it reminds the
# agent to admit the work against the registry of work products (OPS.5). Read-only.

WB_DIR="$(cd "$(dirname "$0")/../../.." && pwd -P)"
# shellcheck source=../../../scripts/paths.sh
. "$WB_DIR/scripts/paths.sh"
# shellcheck source=../../../scripts/hooks.sh
. "$WB_DIR/scripts/hooks.sh"

cat >/dev/null
wb_prompt_answer "$(wb_wp_reminder)"
