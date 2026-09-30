#!/usr/bin/env bats
# Developing the workbench template with a workbench: the template's working copy is an
# ordinary target project, and Claude Code there works by the owner's private base.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  make_sandbox
  export BASE="$SANDBOX/my-workbench" DEV="$SANDBOX/workbench"
  bootstrap "$BASE" --repo "$PRIVATE"
  git clone -q "$TPL" "$DEV"
  wb "$DEV" attach
}

@test "у рабочей копии шаблона нет своих инструкций и хуков Claude Code, только из личной базы" {
  [ ! -e "$DEV/CLAUDE.md" ]
  [ ! -e "$DEV/.claude/settings.json" ]
  grep -qxF @.workbench/AGENTS.md "$DEV/CLAUDE.local.md"
}

@test "начало сессии в рабочей копии шаблона указывает на личную базу" {
  ctx="$(session_context "$DEV")"
  [[ $ctx == *"\$WORKBENCH = $BASE"* ]]
}

@test "скиллы в рабочей копии шаблона берутся из личной базы" {
  for skill in "$BASE"/.agents/skills/*/; do
    name="$(basename "$skill")"
    [ "$(cd "$DEV/.claude/skills/$name" && pwd -P)" = "$BASE/.agents/skills/$name" ]
  done
}

@test "git рабочей копии шаблона не видит личную базу и файлы подключения" {
  [ -z "$(git -C "$DEV" status --porcelain)" ]
}
