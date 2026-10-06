#!/usr/bin/env bats
# Codex and Cursor next to Claude Code. attach connects all three agents to a project with
# local files its git never sees, and the hooks run the way each agent runs them: Codex
# reads its own hooks file in the Claude Code format, Cursor runs the hooks of the
# project's Claude Code settings itself. Tests run in file order.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  make_sandbox
  export BASE="$SANDBOX/my-workbench" P1="$SANDBOX/project-one" CODEX_MD="$HOME/.codex/AGENTS.md"
  bootstrap "$BASE" --repo "$PRIVATE"
  new_project "$P1"
  # The project's own Codex hooks (its git ignores them) and its own skill (tracked).
  mkdir -p "$P1/.codex" "$P1/.agents/skills/own-skill" "$P1/src"
  printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "true"}]}]}}\n' >"$P1/.codex/hooks.json"
  cp "$P1/.codex/hooks.json" "$SANDBOX/codex-hooks.orig"
  printf -- '---\nname: own-skill\ndescription: own skill of the project\n---\n' >"$P1/.agents/skills/own-skill/SKILL.md"
  printf '.codex/\n' >>"$P1/.gitignore"
  git -C "$P1" add .gitignore .agents/skills/own-skill/SKILL.md
  git -C "$P1" commit -qm "own agent files"
  cp "$P1/.git/info/exclude" "$SANDBOX/exclude.orig"
  project_files "$P1" >"$SANDBOX/files.orig"
  mkdir -p "$HOME/.codex"
  printf '# Мои правила для Codex\n\nОтвечать по-русски.\n' >"$CODEX_MD"
  cp "$CODEX_MD" "$SANDBOX/codex-md.orig"
  wb "$P1" attach
}

# names_base_file <file> <path in the base>: the file names that file of the base, the way
# the agents of this system read paths (C:/... on Windows, where Git Bash says /c/...).
names_base_file() {
  local named
  named="$(grep -oE "[^ ]*/$2" "$1" | head -n 1)"
  [ -n "$named" ] && cmp -s "$named" "$BASE/$2"
}

# codex_context <folder>: the context the session-start hook gives Codex started there.
codex_context() {
  local out
  out="$(codex_hook "$P1" session-start.sh "$(session_input "$1")" "$1")" || return 1
  context_of "$out"
}

@test "Codex получает хуки базы рядом со своими хуками проекта" {
  jq -e '(.hooks.Stop | length) == 1
    and (.hooks.SessionStart | length) > 0
    and (.hooks.UserPromptSubmit | length) > 0
    and .hooks.PreToolUse[0].matcher == "^Bash$"' "$P1/.codex/hooks.json"
}

@test "Codex, запущенный из подпапки: начало сессии называет базу и просит прочитать её инструкции" {
  ctx="$(codex_context "$P1/src")"
  [[ $ctx == *"\$WORKBENCH = $(native "$BASE")"* ]]
  [[ $ctx == *"$(native "$BASE")/AGENTS.md"* ]]
  [[ $ctx == *"прочитай их в начале сессии"* ]]
  [[ $ctx == *"workbench attach --user"* ]]
}

@test "Codex: начало сессии несёт индекс личной памяти, читать его самому не нужно" {
  ctx="$(codex_context "$P1")"
  [[ $ctx == *"$(native "$BASE")/memory/MEMORY.md"* ]]
  [[ $ctx == *"$(cat "$BASE/memory/MEMORY.md")"* ]]
}

@test "хуки Codex в Linux и macOS - команды sh, без commandWindows" {
  if on_windows; then skip "только Linux и macOS"; fi
  jq -e '[.. | objects | select(has("commandWindows"))] | length == 0' "$P1/.codex/hooks.json"
  jq -e '[.hooks.SessionStart[0].hooks[0].command | startswith("WB_AGENT=codex sh ")] | all' "$P1/.codex/hooks.json"
}

@test "строка хука Codex для cmd.exe: запускатель без вложенных кавычек и путей с пробелами" {
  line="$(WB_DIR="$BASE" sh -c '. "$WB_DIR/scripts/paths.sh" && wb_codex_windows_hook_command "$1" "$2" "$3"' - \
    'C:\Program Files\Git\bin\sh.exe' 'C:/Users/me/my project' .workbench/adapters/claude/hooks)"
  [ "$line" = 'workbench.cmd --hook %s' ]
}

@test "Codex: напоминание о реестре РП и защита от git add -A" {
  out="$(codex_hook "$P1" wp-gate-reminder.sh "$(prompt_input "$P1" "сделай отчёт")")"
  [[ $(context_of "$out") == *WP-REGISTRY.md* ]]
  run -0 codex_hook "$P1" destructive-guard.sh "$(bash_input "$P1" "git add -A")"
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  [[ $output == *"BLOCKED:"* ]]
  run -0 codex_hook "$P1" destructive-guard.sh "$(bash_input "$P1" "git status")"
}

@test "Codex: неопределённый вход сторожа тоже даёт явный отказ" {
  run -0 codex_hook "$P1" destructive-guard.sh '{}'
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  [[ $output == *"BLOCKED:"* ]]
}

@test "Cursor получает правило workbench: всегда в силе и ведёт к инструкциям и памяти базы" {
  rule="$P1/.cursor/rules/workbench.mdc"
  grep -qx 'alwaysApply: true' "$rule"
  names_base_file "$rule" AGENTS.md
  names_base_file "$rule" memory/MEMORY.md
}

@test "Cursor выполняет хуки из настроек Claude Code: начало сессии говорит с Cursor" {
  # With the block in the user's CLAUDE.md, Claude Code gets the files by import; Cursor does not.
  wb "$SANDBOX" attach --user
  out="$(cursor_hook "$P1" session-start.sh "$(cursor_session_input "$P1")")"
  ctx="$(context_of "$out")"
  [[ $ctx == *"\$WORKBENCH = $(native "$BASE")"* ]]
  [[ $ctx == *"прочитай их в начале сессии"* ]]
  [[ $ctx == *"$(cat "$BASE/memory/MEMORY.md")"* ]]
  [[ $ctx != *"Claude Code загружает"* ]]
}

@test "Claude Code получает память импортом: индекса в начале сессии нет" {
  ctx="$(session_context "$P1")"
  [[ $ctx == *"Claude Code загружает"* ]]
  [[ $ctx != *"$(cat "$BASE/memory/MEMORY.md")"* ]]
}

@test "защита понимает и команду в формате Cursor" {
  run -2 cursor_hook "$P1" destructive-guard.sh "$(jq -n '{hook_event_name: "beforeShellExecution", command: "git add -A"}')"
  run -0 cursor_hook "$P1" destructive-guard.sh "$(jq -n '{hook_event_name: "beforeShellExecution", command: "git status"}')"
}

@test "скиллы базы видны Codex и Cursor, свой скилл проекта на месте" {
  for skill in "$BASE"/.agents/skills/*/; do
    [ -f "$P1/.agents/skills/$(basename "$skill")/SKILL.md" ]
  done
  [ -f "$P1/.agents/skills/own-skill/SKILL.md" ]
}

@test "git проекта не видит файлы подключения Codex и Cursor" {
  [ -z "$(git -C "$P1" status --porcelain)" ]
}

@test "attach --user пишет в AGENTS.md Codex пути к базе, свой текст владельца сохранён" {
  wb "$SANDBOX" attach --user
  head -n 3 "$CODEX_MD" | cmp - "$SANDBOX/codex-md.orig"
  [ "$(grep -c '^<!-- workbench:user begin' "$CODEX_MD")" = 1 ]
  names_base_file "$CODEX_MD" AGENTS.md
  names_base_file "$CODEX_MD" memory/MEMORY.md
  ctx="$(codex_context "$P1")"
  [[ $ctx == *"прочитай их в начале сессии"* ]]
  [[ $ctx != *"workbench attach --user"* ]]
}

@test "detach --user убирает блок из AGENTS.md Codex, свой текст остаётся как был" {
  wb "$SANDBOX" detach --user
  cmp "$CODEX_MD" "$SANDBOX/codex-md.orig"
}

@test "с CODEX_HOME блок пишется в AGENTS.md этой папки" {
  (
    export CODEX_HOME="$SANDBOX/codex-home"
    wb "$SANDBOX" attach --user
  )
  grep -q '^<!-- workbench:user begin' "$SANDBOX/codex-home/AGENTS.md"
  cmp "$CODEX_MD" "$SANDBOX/codex-md.orig"
}

@test "отключение убирает файлы Codex и Cursor и возвращает свои файлы проекта как были" {
  wb "$P1" detach
  [ "$(project_files "$P1")" = "$(cat "$SANDBOX/files.orig")" ]
  cmp "$P1/.codex/hooks.json" "$SANDBOX/codex-hooks.orig"
  cmp "$P1/.git/info/exclude" "$SANDBOX/exclude.orig"
  [ -z "$(git -C "$P1" status --porcelain)" ]
}

@test "хуки Codex, которые проект хранит в git, подключение не трогает и говорит об этом" {
  new_project "$SANDBOX/p-tracked"
  mkdir "$SANDBOX/p-tracked/.codex"
  printf '{"hooks": {}}\n' >"$SANDBOX/p-tracked/.codex/hooks.json"
  git -C "$SANDBOX/p-tracked" add .codex/hooks.json
  git -C "$SANDBOX/p-tracked" commit -qm "team codex hooks"
  run -0 wb "$SANDBOX/p-tracked" attach
  [[ $output == *".codex/hooks.json"* ]]
  [ "$(cat "$SANDBOX/p-tracked/.codex/hooks.json")" = '{"hooks": {}}' ]
  [ -z "$(git -C "$SANDBOX/p-tracked" status --porcelain)" ]
}
