#!/usr/bin/env bats
# The private base opened on its own, e.g. ~/DEV/GITS/my-workbench: setup.sh connects
# Claude Code to the clone itself with local files that git ignores.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  make_sandbox
  export BASE="$SANDBOX/my-workbench"
  bootstrap "$BASE" --repo "$PRIVATE"
}

@test "CLAUDE.local.md подключает инструкции самой базы" {
  grep -qxF @AGENTS.md "$BASE/CLAUDE.local.md"
}

@test "начало сессии в самой базе указывает на неё" {
  ctx="$(session_context "$BASE")"
  [[ $ctx == *"\$WORKBENCH = $BASE"* ]]
}

@test "скиллы базы доступны" {
  for skill in "$BASE"/.agents/skills/*/; do
    [ -f "$BASE/.claude/skills/$(basename "$skill")/SKILL.md" ]
  done
}

@test "git базы не видит файлы подключения" {
  [ -z "$(git -C "$BASE" status --porcelain)" ]
}
