#!/usr/bin/env bats
# Developing the workbench template with a workbench: the template's working copy is an
# ordinary project attached to the base. It works only because the template keeps no
# Claude Code files of its own, which would load a second set of instructions and hooks.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  make_sandbox
  export BASE="$SANDBOX/my-workbench" DEV="$SANDBOX/workbench"
  bootstrap "$BASE" --repo "$PRIVATE"
  git clone -q "$TPL" "$DEV"
  wb "$DEV" attach
}

@test "в рабочей копии шаблона у Claude Code только инструкции и хуки личной базы" {
  [ ! -e "$DEV/CLAUDE.md" ]
  [ ! -e "$DEV/.claude/settings.json" ]
  grep -qxF @.workbench/AGENTS.md "$DEV/CLAUDE.local.md"
  [ "$(jq -r '[.. | objects | .command? | strings] | map(select(contains("/.workbench/"))) | length' "$DEV/.claude/settings.local.json")" = 4 ]
}
