#!/usr/bin/env bats
# First installation into a project whose private repository is still empty and which
# already has its own local Claude Code files; then re-running the setup, detaching and
# attaching again. Tests run in file order.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  make_sandbox
  export P1="$SANDBOX/project-one" WB1="$SANDBOX/project-one/.workbench"
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
  install_into "$P1" --repo "$PRIVATE"
}

@test "личная база создана из шаблона и отправлена в закрытое хранилище" {
  [ "$(git -C "$PRIVATE" rev-parse main)" = "$(git -C "$TPL" rev-parse HEAD)" ]
}

@test "у клона два адреса: личная база (origin) и шаблон (template)" {
  remotes_ok "$WB1"
}

@test "git проекта не видит ни клон, ни файлы подключения" {
  [ -z "$(git -C "$P1" status --porcelain)" ]
}

@test "клон исключён в .git/info/exclude проекта" {
  grep -qxF /.workbench/ "$P1/.git/info/exclude"
}

@test "FPF: рабочая копия на закреплённом издании" {
  [ "$(git -C "$WB1/.fpf" rev-parse HEAD)" = "$FPF_PINNED" ]
}

@test "FPF: скачана одна ревизия, без истории и новых изданий" {
  only_pinned_fetched "$WB1"
}

@test "FPF: рабочая копия заперта" {
  git -C "$WB1" worktree list --porcelain | grep -q '^locked'
}

@test "FPF: ссылка .fpf/.git относительная" {
  grep -q '^gitdir: \.\./\.git/worktrees/' "$WB1/.fpf/.git"
}

@test "проверки git в личной базе включены" {
  [ "$(git -C "$WB1" config core.hooksPath)" = .githooks ]
}

@test "свой CLAUDE.local.md проекта сохранён, workbench дописал к нему свой блок" {
  head -n 3 "$P1/CLAUDE.local.md" | cmp - "$SANDBOX/claude-local.orig"
  grep -q '^<!-- workbench:attach begin' "$P1/CLAUDE.local.md"
}

@test "CLAUDE.local.md подключает инструкции workbench" {
  grep -qxF @.workbench/AGENTS.md "$P1/CLAUDE.local.md"
}

@test "CLAUDE.local.md подключает личную память владельца" {
  grep -qxF @.workbench/memory/MEMORY.md "$P1/CLAUDE.local.md"
}

@test "свои настройки Claude Code в проекте сохранены, хуки добавлены" {
  jq -e '(.permissions.allow | index("Bash(ls:*)")) != null
    and (.hooks.SessionStart | length) > 0
    and (.hooks.UserPromptSubmit | length) > 0
    and .hooks.PreToolUse[0].matcher == "Bash"' "$P1/.claude/settings.local.json"
}

@test "копия прежних настроек лежит рядом" {
  cmp "$P1/.claude/settings.local.json.wb-backup" "$SANDBOX/settings.orig"
}

@test "скиллы workbench доступны из проекта" {
  skills_linked "$P1"
}

@test "повторный setup.sh не задваивает подключение" {
  sh "$WB1/scripts/setup.sh"
  [ "$(grep -c '^# workbench:attach begin$' "$P1/.git/info/exclude")" = 1 ]
  [ "$(grep -c '^@.workbench/AGENTS.md$' "$P1/CLAUDE.local.md")" = 1 ]
  cmp "$P1/.claude/settings.local.json.wb-backup" "$SANDBOX/settings.orig"
}

@test "отключение возвращает проект в прежнее состояние" {
  sh "$WB1/scripts/attach.sh" --detach "$P1"
  [ "$(project_files "$P1")" = "$(cat "$SANDBOX/files.orig")" ]
  cmp "$P1/.claude/settings.local.json" "$SANDBOX/settings.orig"
  cmp "$P1/CLAUDE.local.md" "$SANDBOX/claude-local.orig"
  exclude_restored "$P1" "$SANDBOX/exclude.orig"
  [ -z "$(git -C "$P1" status --porcelain)" ]
}

@test "повторное подключение после отключения" {
  sh "$WB1/scripts/attach.sh" "$P1"
  grep -qxF @.workbench/AGENTS.md "$P1/CLAUDE.local.md"
  [ -z "$(git -C "$P1" status --porcelain)" ]
}
