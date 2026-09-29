#!/usr/bin/env bash
# Offline end-to-end smoke test of the installer and the Claude Code adapter.
#
# Everything runs in a throwaway sandbox: a local bare repository stands in for the
# owner's private repository, a tiny local repository stands in for FPF, and the
# template is a snapshot of this working tree, uncommitted changes included. The
# owner's projects, repositories and git settings are never touched.
#
# Usage: bash tests/smoke.sh          the sandbox is removed when every check passes
#        KEEP=1 bash tests/smoke.sh   keep the sandbox for inspection
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Keep the caller's context out of the sandbox: variables of a surrounding git hook
# (GIT_DIR and friends), installer settings and the guard's owner-only bypass.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars) CC_ALLOW_DESTRUCTIVE_INPUT \
  WORKBENCH_TEMPLATE WORKBENCH_REPO WORKBENCH_BASE WORKBENCH_NAME WORKBENCH_YES

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/workbench-smoke.XXXXXX")"
SANDBOX="$(cd "$SANDBOX" && pwd -P)"
LOG="$SANDBOX/smoke.log"
PASSED=0
FAILED=0

cleanup() {
  local rc=$?
  if [ "$rc" = 0 ] && [ "${KEEP:-0}" != 1 ]; then
    rm -rf "$SANDBOX"
  else
    printf '\nПесочница оставлена: %s (вывод команд: %s)\n' "$SANDBOX" "$LOG" >&2
  fi
}
trap cleanup EXIT

# Git settings of the sandbox only: identity and main as the default branch.
export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name "workbench smoke test"
git config --global user.email "smoke@example.invalid"
git config --global init.defaultBranch main

# --- reporting ------------------------------------------------------------------

section() {
  printf '\n%s\n' "$1"
}

# check <description> <command...>: passes when the command succeeds; its output
# goes to the log.
check() {
  local what="$1"
  shift
  printf '\n## %s\n' "$what" >>"$LOG"
  if "$@" >>"$LOG" 2>&1; then
    PASSED=$((PASSED + 1))
    printf '  ✓ %s\n' "$what"
  else
    FAILED=$((FAILED + 1))
    printf '  ✗ %s\n' "$what"
  fi
}

# require <description> <command...>: a check the rest of the run depends on.
require() {
  local before="$FAILED"
  check "$@"
  if [ "$FAILED" != "$before" ]; then
    printf '\nКонец вывода команд:\n' >&2
    tail -n 40 "$LOG" >&2
    exit 1
  fi
}

# --- predicates -------------------------------------------------------------------

refused() {
  ! "$@"
}

same() {
  [ "$1" = "$2" ]
}

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

# mentions <text> <fragment...>: the text contains every fragment.
mentions() {
  local text="$1" fragment
  shift
  for fragment in "$@"; do
    contains "$text" "$fragment" || return 1
  done
}

has_line() {
  grep -qxF -- "$2" "$1"
}

# exits_with <code> <command...>
exits_with() {
  local want="$1" rc=0
  shift
  "$@" || rc=$?
  [ "$rc" = "$want" ]
}

remotes_ok() {
  same "$(git -C "$1" remote get-url origin)" "$PRIVATE" &&
    same "$(git -C "$1" remote get-url template)" "$TPL"
}

# Only the pinned FPF edition is in the clone: neither its history nor later editions.
only_pinned_fetched() {
  git -C "$1" cat-file -e "$FPF_PINNED^{commit}" &&
    ! git -C "$1" cat-file -e "$FPF_OLD^{commit}" 2>/dev/null &&
    ! git -C "$1" cat-file -e "$FPF_NEWER^{commit}" 2>/dev/null
}

fpf_locked() {
  git -C "$1" worktree list --porcelain | grep -q '^locked'
}

# worktree_at <clone> <path>: the clone's record of its FPF worktree points at path.
worktree_at() {
  git -C "$1" worktree list --porcelain | grep -qxF "worktree $2"
}

# The project's own local settings survive and the adapter's hooks are added.
settings_merged() {
  jq -e '(.permissions.allow | index("Bash(ls:*)")) != null
    and (.hooks.SessionStart | length) > 0
    and (.hooks.UserPromptSubmit | length) > 0
    and .hooks.PreToolUse[0].matcher == "Bash"' "$1/.claude/settings.local.json"
}

skills_linked() {
  local skill
  for skill in "$1"/.workbench/.agents/skills/*/; do
    [ -f "$1/.claude/skills/$(basename "$skill")/SKILL.md" ] || return 1
  done
}

# The exclude file is the original one plus the two lines that keep the clone out.
exclude_restored() {
  { grep -vxF -e '# workbench clone: personal, never commit' -e '/.workbench/' "$1/.git/info/exclude" || true; } |
    cmp -s - "$2"
}

# --- actions ----------------------------------------------------------------------

# new_project <dir>: a git project with one commit that ignores local Claude settings.
new_project() {
  git init -q "$1"
  printf '# %s\n' "$(basename "$1")" >"$1/README.md"
  printf '.claude/settings.local.json\n' >"$1/.gitignore"
  git -C "$1" add README.md .gitignore
  git -C "$1" commit -qm "project start"
  mkdir -p "$1/.git/info"
  touch "$1/.git/info/exclude"
}

# project_files <dir>: the project's files outside .git and .workbench.
project_files() {
  (cd "$1" && find . -path ./.git -prune -o -path ./.workbench -prune -o -print) | LC_ALL=C sort
}

# run_installer <project> [args...]: runs install.sh the way `curl ... | bash -s -- args` does.
run_installer() {
  local project="$1"
  shift
  (cd "$project" && bash -s -- --template "$TPL" "$@" <"$TPL/install.sh")
}

# hook <project> <script> <json>: runs a hook command from the project's generated
# settings the way Claude Code does: through a shell, in the project, with CLAUDE_PROJECT_DIR.
hook() {
  local cmd
  cmd="$(jq -r --arg s "/$2" '[.. | objects | .command? | strings | select(contains($s))][0] // empty' \
    "$1/.claude/settings.local.json")"
  [ -n "$cmd" ] || return 90
  (cd "$1" && printf '%s' "$3" | CLAUDE_PROJECT_DIR="$1" sh -c "$cmd")
}

# context <project> <script> <json>: the additionalContext the hook returns.
context() {
  { hook "$@" || true; } | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

session_input() {
  jq -n --arg cwd "$1" '{hook_event_name: "SessionStart", source: "startup", cwd: $cwd}'
}

prompt_input() {
  jq -n --arg cwd "$1" --arg p "$2" '{hook_event_name: "UserPromptSubmit", prompt: $p, cwd: $cwd}'
}

bash_input() {
  jq -n --arg cwd "$1" --arg c "$2" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}, cwd: $cwd}'
}

# commit_note <clone> <text>: commits a line in the fleeting notes; a refused commit
# is rolled back.
commit_note() {
  printf '%s\n' "$2" >>"$1/inbox/fleeting-notes.md"
  git -C "$1" add -- inbox/fleeting-notes.md
  if git -C "$1" commit -qm "smoke: note"; then
    return 0
  fi
  git -C "$1" restore --staged --worktree -- inbox/fleeting-notes.md
  return 1
}

note_and_push() {
  commit_note "$1" "$2" && git -C "$1" push -q origin HEAD
}

# --- sandbox ----------------------------------------------------------------------

# A tiny FPF stand-in with three editions; the middle one is pinned.
FPF_SRC="$SANDBOX/fpf"
fpf_edition() {
  printf '## A.1 %s edition\n### A.1:End\n' "$1" >"$FPF_SRC/FPF-Spec.md" &&
    git -C "$FPF_SRC" add FPF-Spec.md USING-FPF.md &&
    git -C "$FPF_SRC" commit -qm "$1 edition" &&
    git -C "$FPF_SRC" rev-parse HEAD
}
git init -q "$FPF_SRC"
printf '# Using FPF (smoke test stand-in)\n' >"$FPF_SRC/USING-FPF.md"
FPF_OLD="$(fpf_edition old)"
FPF_PINNED="$(fpf_edition pinned)"
FPF_NEWER="$(fpf_edition newer)"

# The template: this working tree with its uncommitted changes, FPF pointed at the stand-in.
TPL="$SANDBOX/template"
mkdir "$TPL"
git -C "$ROOT" ls-files -z --cached --others --exclude-standard |
  while IFS= read -r -d '' f; do
    if [ -e "$ROOT/$f" ] || [ -L "$ROOT/$f" ]; then printf '%s\n' "$f"; fi
  done >"$SANDBOX/template.files"
tar -C "$ROOT" -cf - -T "$SANDBOX/template.files" | tar -C "$TPL" -xf -
printf 'url=file://%s\ncommit=%s\n' "$FPF_SRC" "$FPF_PINNED" >"$TPL/.fpf-edition"
git init -q "$TPL"
git -C "$TPL" add --pathspec-from-file="$SANDBOX/template.files"
git -C "$TPL" commit -qm "template snapshot"

# The owner's private repository, still empty.
PRIVATE="$SANDBOX/private.git"
git init -q --bare "$PRIVATE"

printf 'Проверка workbench\n  шаблон: рабочая копия %s\n  песочница: %s\n' "$ROOT" "$SANDBOX"

# --- 1. first project: the private repository is created from the template ----------

P1="$SANDBOX/project-one"
WB1="$P1/.workbench"
new_project "$P1"
mkdir "$P1/.claude"
printf '{"permissions": {"allow": ["Bash(ls:*)"]}}\n' >"$P1/.claude/settings.local.json"
cp "$P1/.claude/settings.local.json" "$SANDBOX/p1-settings.orig"
cp "$P1/.git/info/exclude" "$SANDBOX/p1-exclude.orig"
project_files "$P1" >"$SANDBOX/p1-files.orig"

section "1. Установка в новый проект, личная база ещё пустая"
require "установщик отработал" run_installer "$P1" --repo "$PRIVATE"
check "личная база создана из шаблона и отправлена в закрытое хранилище" \
  same "$(git -C "$PRIVATE" rev-parse -q --verify main)" "$(git -C "$TPL" rev-parse HEAD)"
check "у клона два адреса: личная база (origin) и шаблон (template)" remotes_ok "$WB1"
check "git проекта не видит ни клон, ни файлы подключения" same "$(git -C "$P1" status --porcelain)" ""
check "клон исключён в .git/info/exclude проекта" has_line "$P1/.git/info/exclude" "/.workbench/"
check "FPF: рабочая копия на закреплённом издании" same "$(git -C "$WB1/.fpf" rev-parse HEAD)" "$FPF_PINNED"
check "FPF: скачана одна ревизия, без истории и новых изданий" only_pinned_fetched "$WB1"
check "FPF: рабочая копия заперта" fpf_locked "$WB1"
check "FPF: ссылка .fpf/.git относительная" grep -q '^gitdir: \.\./\.git/worktrees/' "$WB1/.fpf/.git"
check "проверки git в личной базе включены" same "$(git -C "$WB1" config core.hooksPath)" ".githooks"
check "CLAUDE.local.md подключает инструкции workbench" has_line "$P1/CLAUDE.local.md" "@.workbench/AGENTS.md"
check "свои настройки Claude Code в проекте сохранены, хуки добавлены" settings_merged "$P1"
check "копия прежних настроек лежит рядом" \
  cmp -s "$P1/.claude/settings.local.json.wb-backup" "$SANDBOX/p1-settings.orig"
check "скиллы workbench доступны из проекта" skills_linked "$P1"

# --- 2. hooks ---------------------------------------------------------------------

section "2. Хуки, запущенные так же, как их запускает Claude Code"
ctx="$(context "$P1" session-start.sh "$(session_input "$P1")")"
check "начало сессии: пути к workbench и FPF, закреплённое издание" \
  mentions "$ctx" "\$WORKBENCH = $WB1" "\$FPF = $WB1/.fpf (издание ${FPF_PINNED:0:7})"
check "начало сессии: без предупреждений" refused contains "$ctx" "ВНИМАНИЕ"
check "начало сессии: правило допуска задачи" mentions "$ctx" "OPS.5"
check "сообщение владельца: напоминание о РП" \
  mentions "$(context "$P1" wp-gate-reminder.sh "$(prompt_input "$P1" "сделай отчёт")")" "WP-REGISTRY.md"
check "«Закрывай» вызывает скилл закрытия" \
  mentions "$(context "$P1" close-gate-reminder.sh "$(prompt_input "$P1" "Закрывай")")" "close-session"
check "обычное сообщение закрытие не вызывает" \
  same "$(hook "$P1" close-gate-reminder.sh "$(prompt_input "$P1" "покажи статус")")" "{}"
for cmd in "git add -A" "git push --force origin main" "cd /tmp"; do
  check "защита блокирует: $cmd" exits_with 2 hook "$P1" destructive-guard.sh "$(bash_input "$P1" "$cmd")"
done
check "защита пропускает: git status" exits_with 0 hook "$P1" destructive-guard.sh "$(bash_input "$P1" "git status")"

# --- 3. checks before saving in the private base ------------------------------------

section "3. Проверки перед сохранением в личной базе"
printf 'acme-internal\n' >>"$(git -C "$WB1" rev-parse --absolute-git-dir)/info/company-markers"
check "запись с маркером компании не сохраняется" refused commit_note "$WB1" "Встреча по ACME-Internal"
# Split so that the file itself holds no key-like string.
check "запись с текстом, похожим на ключ доступа, не сохраняется" \
  refused commit_note "$WB1" "key AKIA""SMOKETESTKEY0000"

# --- 4. re-run and detach -----------------------------------------------------------

section "4. Повторная подготовка и отключение"
require "setup.sh запускается повторно" bash "$WB1/scripts/setup.sh"
check "подключение не задвоилось" same "$(grep -c '^# workbench:attach begin$' "$P1/.git/info/exclude")" 1
check "копия прежних настроек по-прежнему исходная" \
  cmp -s "$P1/.claude/settings.local.json.wb-backup" "$SANDBOX/p1-settings.orig"
require "отключение отработало" bash "$WB1/scripts/attach.sh" --detach "$P1"
check "файлы проекта те же, что до установки" same "$(project_files "$P1")" "$(cat "$SANDBOX/p1-files.orig")"
check "свои настройки Claude Code восстановлены байт в байт" \
  cmp -s "$P1/.claude/settings.local.json" "$SANDBOX/p1-settings.orig"
check "в .git/info/exclude осталось только исключение клона" exclude_restored "$P1" "$SANDBOX/p1-exclude.orig"
check "git проекта чист" same "$(git -C "$P1" status --porcelain)" ""
require "повторное подключение отработало" bash "$WB1/scripts/attach.sh" "$P1"

# --- 5. second project: the private repository already exists -----------------------

section "5. Второй проект, личная база уже есть"
P2="$SANDBOX/project-two"
WB2="$P2/.workbench"
new_project "$P2"
# A bare repository whose HEAD names a missing branch, as `git init --bare` leaves it
# where master is the default branch.
git -C "$PRIVATE" symbolic-ref HEAD refs/heads/master
require "установщик отработал" run_installer "$P2" --repo "$PRIVATE"
check "склонирована существующая личная база, ветка main" same "$(git -C "$WB2" rev-parse --abbrev-ref HEAD)" main
check "клон совпадает с личной базой" same "$(git -C "$WB2" rev-parse HEAD)" "$(git -C "$PRIVATE" rev-parse main)"
check "у клона два адреса: личная база и шаблон" remotes_ok "$WB2"
check "FPF: закреплённое издание" same "$(git -C "$WB2/.fpf" rev-parse HEAD)" "$FPF_PINNED"
check "git проекта не видит ни клон, ни файлы подключения" same "$(git -C "$P2" status --porcelain)" ""

# --- 6. exchange through the private base -------------------------------------------

section "6. Обмен между проектами через личную базу"
require "запись во втором проекте сохранена и отправлена" note_and_push "$WB2" "заметка из второго проекта"
require "установщик, запущенный повторно в первом проекте, отработал" run_installer "$P1"
check "первый проект получил запись второго" \
  same "$(git -C "$WB1" rev-parse HEAD)" "$(git -C "$PRIVATE" rev-parse main)"
pushed="$(git -C "$PRIVATE" rev-parse main)"
git -C "$WB1" commit -q --amend -m "smoke: rewritten history"
check "перезапись истории личной базы отклонена" refused git -C "$WB1" push -q --force origin HEAD:main
check "личная база не изменилась" same "$(git -C "$PRIVATE" rev-parse main)" "$pushed"

# --- 7. moved project ---------------------------------------------------------------

section "7. Папка проекта перенесена (например, смонтирована в контейнер)"
P2M="$SANDBOX/moved/project-two"
mkdir "$SANDBOX/moved"
mv "$P2" "$P2M"
check "FPF открывается по относительной ссылке" same "$(git -C "$P2M/.workbench/.fpf" rev-parse HEAD)" "$FPF_PINNED"
check "скиллы доступны" skills_linked "$P2M"
check "начало сессии видит закреплённое издание" \
  mentions "$(context "$P2M" session-start.sh "$(session_input "$P2M")")" "\$FPF = $P2M/.workbench/.fpf (издание ${FPF_PINNED:0:7})"
require "setup.sh на новом месте отработал" bash "$P2M/.workbench/scripts/setup.sh"
check "запись о рабочей копии FPF указывает на новое место" worktree_at "$P2M/.workbench" "$P2M/.workbench/.fpf"

printf '\nИтог: пройдено %d, не пройдено %d.\n' "$PASSED" "$FAILED"
[ "$FAILED" = 0 ]
