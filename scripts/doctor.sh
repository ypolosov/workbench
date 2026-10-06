#!/bin/sh
# Read-only installation diagnostics; JSON and text describe the same checks.
set -eu
WB_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$WB_DIR/scripts/paths.sh"
json=0
project=""
report=""
while [ $# -gt 0 ]; do
  case $1 in
    --json)
      json=1
      shift
      ;;
    --project)
      project=${2:?--project requires a folder}
      shift 2
      ;;
    --report)
      report=${2:?--report requires a file}
      shift 2
      ;;
    -h | --help)
      printf 'workbench doctor [--json] [--project <folder>]\n'
      exit 0
      ;;
    *)
      printf 'workbench doctor: unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done
checks='[]'
if ! command -v jq >/dev/null 2>&1; then
  if [ "$json" = 1 ]; then
    printf '%s\n' '{"ready":false,"checks":[{"id":"jq","status":"error","message":"jq unavailable"}]}'
  else printf 'workbench: обработка настроек недоступна; повторите установку\n' >&2; fi
  exit 1
fi
if [ -z "$project" ]; then
  current_project="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$current_project" ] && [ "$current_project" != "$WB_DIR" ] &&
    { [ -e "$current_project/.workbench" ] || [ -L "$current_project/.workbench" ]; }; then
    project=$current_project
  elif [ -f "$WB_DIR/.runtime/install.json" ]; then
    project="$(jq -r '.project // empty' "$WB_DIR/.runtime/install.json")"
  fi
fi
if [ -n "$project" ]; then
  if wb_windows; then project="$(cygpath -u "$project")"; fi
  case "$project" in /*) ;; *) project="$PWD/$project" ;; esac
fi
add_check() {
  checks="$(printf '%s' "$checks" | jq --arg id "$1" --arg status "$2" --arg message "$3" \
    '. + [{id: $id, status: $status, message: $message}]')"
}
if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then add_check git ok 'Git запускается'; else add_check git error 'Git недоступен'; fi
if command -v jq >/dev/null 2>&1; then add_check jq ok 'Обработка настроек доступна'; else
  printf 'workbench: jq недоступен; повторите установку\n' >&2
  exit 1
fi
if [ -f "$WB_DIR/AGENTS.md" ] && [ -f "$WB_DIR/memory/MEMORY.md" ]; then
  add_check base ok 'Инструкции и индекс памяти доступны'
else add_check base error 'База неполна'; fi
if [ -f "$WB_DIR/.fpf-edition" ] && [ -f "$FPF_DIR/USING-FPF.md" ] &&
  [ "$(git -C "$FPF_DIR" rev-parse HEAD 2>/dev/null || true)" = "$(wb_fpf_edition commit)" ]; then
  add_check fpf ok 'Закреплённое издание FPF готово'
else add_check fpf error 'Издание FPF не подготовлено'; fi
if [ "$(git -C "$WB_DIR" config core.hooksPath 2>/dev/null || true)" = .githooks ]; then
  add_check git_hooks ok 'Проверки сохранения подключены'
else add_check git_hooks error 'Проверки сохранения не подключены'; fi
if [ -f "$WB_DIR/.runtime/program-version" ]; then
  program_version="$(cat "$WB_DIR/.runtime/program-version")"
  if git -C "$WB_DIR" merge-base --is-ancestor "$program_version" HEAD 2>/dev/null; then
    add_check program_history ok 'Версия программы записана в истории шаблона и базы'
  else add_check program_history error 'Обновление программы не записано в Git; выполните workbench update'; fi
fi
if command -v workbench >/dev/null 2>&1 || command -v workbench.cmd >/dev/null 2>&1; then
  add_check command ok 'Команда доступна'
else add_check command error 'Команда недоступна; повторите установку'; fi
if wb_user_attached && wb_codex_attached; then
  add_check instructions ok 'Инструкции подключены на уровне пользователя'
else add_check instructions error 'Подключение инструкций не завершено'; fi
if [ -n "$project" ]; then
  if [ -f "$project/.workbench/AGENTS.md" ] && [ -f "$project/.codex/hooks.json" ] && [ -f "$project/.claude/settings.local.json" ]; then
    add_check project ok 'Проект подключён'
  else add_check project error 'Подключение проекта неполно'; fi
  probe_cwd=$project
else probe_cwd=$WB_DIR; fi
if command -v codex >/dev/null 2>&1; then
  . "$WB_DIR/scripts/codex-rpc.sh"
  codex_view="$(wb_codex_list_hooks "$probe_cwd")" || codex_view=""
  if [ -n "$codex_view" ] && printf '%s' "$codex_view" | jq -e '
    [.result.data[].hooks[] | select(.handlerType == "command") |
      select((.command | startswith("workbench.cmd --hook ")) or
        (.command | startswith("WB_AGENT=codex sh ") and contains("adapters/claude/hooks/")))] |
    length >= 4 and all(.[]; .enabled and (.trustStatus == "trusted" or .trustStatus == "managed"))' >/dev/null; then
    add_check codex_hooks ok 'Codex подтверждает, что хуки активны и одобрены'
  else add_check codex_hooks error 'Codex не подтвердил готовность хуков'; fi
else
  add_check codex_cli warning 'Codex CLI не установлен; его запуск не проверен'
fi
if command -v claude >/dev/null 2>&1 && claude --version >/dev/null 2>&1; then
  add_check claude_cli ok 'Claude Code запускается; доступность аккаунта не проверялась'
else add_check claude_cli warning 'Claude Code не установлен или не запускается'; fi
probe_input="$(jq -n --arg cwd "$probe_cwd" '{cwd: $cwd, source: "startup", hook_event_name: "SessionStart"}')"
probe_context="$(printf '%s' "$probe_input" | WB_AGENT=codex sh "$WB_DIR/adapters/claude/hooks/session-start.sh")" || probe_context=""
if printf '%s' "$probe_context" | jq -e '.hookSpecificOutput.additionalContext | contains("workbench")' >/dev/null; then
  add_check context ok 'Хук начала сессии возвращает контекст'
else add_check context error 'Хук начала сессии не возвращает контекст'; fi
probe_input="$(jq -n '{tool_name: "Bash", tool_input: {command: "cd /tmp"}}')"
probe_guard="$(printf '%s' "$probe_input" | WB_AGENT=codex sh "$WB_DIR/adapters/claude/hooks/destructive-guard.sh")" || probe_guard=""
if printf '%s' "$probe_guard" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; then
  add_check guard ok 'Сторож возвращает явный отказ'
else add_check guard error 'Сторож не возвращает отказ'; fi
project_display=""
[ -z "$project" ] || project_display="$(wb_native_path "$project")"
result="$(printf '%s' "$checks" | jq --arg base "$(wb_native_path "$WB_DIR")" --arg project "$project_display" \
  '{base: $base, project: $project, ready: (all(.[]; .status != "error")), checks: .}')"
if [ -n "$report" ]; then printf '%s\n' "$result" >"$report"; fi
if [ "$json" = 1 ]; then printf '%s\n' "$result"; else
  [ -z "$project" ] || printf 'Проект: %s\n' "$project_display"
  printf '%s' "$result" | jq -r '.checks[] | "[" + .status + "] " + .message'
  if printf '%s' "$result" | jq -e '.ready' >/dev/null; then printf '\nworkbench: проверки установки пройдены.\n'; else printf '\nworkbench: установка требует исправления.\n'; fi
fi
printf '%s' "$result" | jq -e '.ready' >/dev/null
