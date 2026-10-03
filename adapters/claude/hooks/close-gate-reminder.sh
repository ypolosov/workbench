#!/bin/sh
# UserPromptSubmit hook in Claude Code's protocol; Codex takes it as it is, and Cursor runs
# it from the project's Claude Code settings. When the owner asks to close the session, it
# tells the agent to run the close-session skill; otherwise it adds nothing. Read-only.

WB_DIR="$(cd "$(dirname "$0")/../../.." && pwd -P)"
# shellcheck source=../../../scripts/paths.sh
. "$WB_DIR/scripts/paths.sh"
# shellcheck source=../../../scripts/hooks.sh
. "$WB_DIR/scripts/hooks.sh"

wb_prompt_answer "$(wb_close_reminder "$(wb_prompt)")"
