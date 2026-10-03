#!/usr/bin/env bats
# The hooks in Claude Code's protocol, run the way Claude Code runs them: the command from
# the project's generated settings, through a shell, with CLAUDE_PROJECT_DIR.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  make_sandbox
  export BASE="$SANDBOX/my-workbench" P1="$SANDBOX/project-one"
  bootstrap "$BASE" --repo "$PRIVATE"
  new_project "$P1"
  wb "$P1" attach
}

@test "начало сессии: пути к workbench и FPF, закреплённое издание" {
  ctx="$(session_context "$P1")"
  [[ $ctx == *"\$WORKBENCH = $BASE"* ]]
  [[ $ctx == *"\$FPF = $BASE/.fpf (издание ${FPF_PINNED:0:7})"* ]]
}

@test "без инструкций базы на уровне пользователя начало сессии просит прочитать её файлы и называет команду" {
  ctx="$(session_context "$P1")"
  [[ $ctx == *"$BASE/AGENTS.md"* ]]
  [[ $ctx == *"$BASE/memory/MEMORY.md"* ]]
  [[ $ctx == *"прочитай оба файла"* ]]
  [[ $ctx == *"workbench attach --user"* ]]
}

@test "начало сессии: исполняемые части не изменены, предупреждений нет" {
  ctx="$(session_context "$P1")"
  [[ $ctx == *"Исполняемые части workbench совпадают с сохранёнными"* ]]
  [[ $ctx != *ВНИМАНИЕ* ]]
}

@test "сообщение владельца: напоминание о реестре РП" {
  ctx="$(prompt_context "$P1" wp-gate-reminder.sh "сделай отчёт")"
  [[ $ctx == *WP-REGISTRY.md* ]]
}

@test "Закрывай с заглавной буквы вызывает скилл закрытия" {
  ctx="$(prompt_context "$P1" close-gate-reminder.sh "Закрывай")"
  [[ $ctx == *close-session* ]]
}

@test "закрывай в многострочном сообщении вызывает скилл закрытия, даже с переводом строки прямо в JSON" {
  ctx="$(prompt_context "$P1" close-gate-reminder.sh "$(printf 'готово\nзакрывай')")"
  [[ $ctx == *close-session* ]]
  raw="$(printf '{"hook_event_name": "UserPromptSubmit", "prompt": "готово\n\tзакрывай", "cwd": "%s"}' "$P1")"
  [[ $(context_of "$(hook "$P1" close-gate-reminder.sh "$raw")") == *close-session* ]]
}

@test "обычное сообщение закрытие не вызывает" {
  run -0 hook "$P1" close-gate-reminder.sh "$(prompt_input "$P1" "покажи статус")"
  [ "$output" = "{}" ]
}

@test "защита блокирует git add -A" {
  run -2 hook "$P1" destructive-guard.sh "$(bash_input "$P1" "git add -A")"
}

@test "защита пропускает git status" {
  run -0 hook "$P1" destructive-guard.sh "$(bash_input "$P1" "git status")"
}
