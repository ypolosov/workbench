#!/usr/bin/env bats
# Attach and detach: the base of the machine is connected to a project that already has
# its own local Claude Code files, then disconnected. Tests run in file order.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  make_sandbox
  export BASE="$SANDBOX/my-workbench" P1="$SANDBOX/project-one"
  bootstrap "$BASE" --repo "$PRIVATE"
  new_project "$P1"
  mkdir "$P1/.claude"
  printf '{"permissions": {"allow": ["Bash(ls:*)"]}}\n' >"$P1/.claude/settings.local.json"
  cp "$P1/.claude/settings.local.json" "$SANDBOX/settings.orig"
  # The owner's own local instructions for this project, ignored by its git.
  printf 'CLAUDE.local.md\n' >>"$P1/.gitignore"
  git -C "$P1" commit -qam "ignore local instructions"
  printf '# Мои заметки по проекту\n\nЛичные правила для этого проекта.\n' >"$P1/CLAUDE.local.md"
  cp "$P1/CLAUDE.local.md" "$SANDBOX/claude-local.orig"
  cp "$P1/.git/info/exclude" "$SANDBOX/exclude.orig"
  project_files "$P1" >"$SANDBOX/files.orig"
  wb "$P1" attach
}

@test ".workbench в проекте - ссылка на личную базу машины" {
  [ -L "$P1/.workbench" ]
  [ "$(cd "$P1/.workbench" && pwd -P)" = "$BASE" ]
}

@test "git проекта не видит ни ссылку, ни файлы подключения" {
  [ -z "$(git -C "$P1" status --porcelain)" ]
}

@test "свой CLAUDE.local.md проекта сохранён, workbench дописал к нему свой блок" {
  head -n 3 "$P1/CLAUDE.local.md" | cmp - "$SANDBOX/claude-local.orig"
  grep -q '^<!-- workbench:attach begin' "$P1/CLAUDE.local.md"
}

@test "CLAUDE.local.md подключает инструкции и личную память из базы" {
  grep -qxF @.workbench/AGENTS.md "$P1/CLAUDE.local.md"
  grep -qxF @.workbench/memory/MEMORY.md "$P1/CLAUDE.local.md"
}

@test "свои настройки Claude Code в проекте сохранены, хуки добавлены" {
  jq -e '(.permissions.allow | index("Bash(ls:*)")) != null
    and (.hooks.SessionStart | length) > 0
    and (.hooks.UserPromptSubmit | length) > 0
    and .hooks.PreToolUse[0].matcher == "Bash"' "$P1/.claude/settings.local.json"
}

@test "скиллы базы доступны из проекта" {
  skills_linked "$P1"
}

@test "повторное подключение не задваивает подключение" {
  wb "$P1" attach
  [ "$(grep -c '^# workbench:attach begin$' "$P1/.git/info/exclude")" = 1 ]
  [ "$(grep -c '^@.workbench/AGENTS.md$' "$P1/CLAUDE.local.md")" = 1 ]
  cmp "$P1/.claude/settings.local.json.wb-backup" "$SANDBOX/settings.orig"
}

@test "отключение возвращает проект в прежнее состояние, а база остаётся" {
  wb "$P1" detach
  [ ! -e "$P1/.workbench" ] && [ ! -L "$P1/.workbench" ]
  [ "$(project_files "$P1")" = "$(cat "$SANDBOX/files.orig")" ]
  cmp "$P1/.claude/settings.local.json" "$SANDBOX/settings.orig"
  cmp "$P1/CLAUDE.local.md" "$SANDBOX/claude-local.orig"
  cmp "$P1/.git/info/exclude" "$SANDBOX/exclude.orig"
  [ -z "$(git -C "$P1" status --porcelain)" ]
  [ -f "$BASE/AGENTS.md" ]
  [ -z "$(git -C "$BASE" status --porcelain)" ]
}

@test "повторное подключение после отключения" {
  wb "$P1" attach
  [ -L "$P1/.workbench" ]
  grep -qxF @.workbench/AGENTS.md "$P1/CLAUDE.local.md"
  [ -z "$(git -C "$P1" status --porcelain)" ]
}
