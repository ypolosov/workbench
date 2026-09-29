#!/usr/bin/env bats
# The Claude Code adapter's hooks, run the way Claude Code runs them: the command from
# the project's generated settings, through a shell, with CLAUDE_PROJECT_DIR.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  make_sandbox
  export P1="$SANDBOX/project-one" WB1="$SANDBOX/project-one/.workbench"
  new_project "$P1"
  install_into "$P1" --repo "$PRIVATE"
}

@test "начало сессии: пути к workbench и FPF, закреплённое издание" {
  ctx="$(session_context "$P1")"
  [[ $ctx == *"\$WORKBENCH = $WB1"* ]]
  [[ $ctx == *"\$FPF = $WB1/.fpf (издание ${FPF_PINNED:0:7})"* ]]
}

@test "начало сессии: исполняемые части не изменены, предупреждений нет" {
  ctx="$(session_context "$P1")"
  [[ $ctx == *"Исполняемые части workbench совпадают с сохранёнными"* ]]
  [[ $ctx != *ВНИМАНИЕ* ]]
}

@test "начало сессии: правило допуска задачи" {
  ctx="$(session_context "$P1")"
  [[ $ctx == *OPS.5* ]]
}

@test "сообщение владельца: напоминание о реестре РП" {
  ctx="$(prompt_context "$P1" wp-gate-reminder.sh "сделай отчёт")"
  [[ $ctx == *WP-REGISTRY.md* ]]
}

@test "«Закрывай» с заглавной буквы вызывает скилл закрытия" {
  ctx="$(prompt_context "$P1" close-gate-reminder.sh "Закрывай")"
  [[ $ctx == *close-session* ]]
}

@test "обычное сообщение закрытие не вызывает" {
  run -0 hook "$P1" close-gate-reminder.sh "$(prompt_input "$P1" "покажи статус")"
  [ "$output" = "{}" ]
}

@test "защита блокирует git add -A" {
  run -2 hook "$P1" destructive-guard.sh "$(bash_input "$P1" "git add -A")"
}

@test "защита блокирует git push --force" {
  run -2 hook "$P1" destructive-guard.sh "$(bash_input "$P1" "git push --force origin main")"
}

@test "защита блокирует переход в папку отдельной командой cd" {
  run -2 hook "$P1" destructive-guard.sh "$(bash_input "$P1" "cd /tmp")"
}

@test "защита пропускает git status" {
  run -0 hook "$P1" destructive-guard.sh "$(bash_input "$P1" "git status")"
}
