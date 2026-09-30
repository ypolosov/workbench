#!/usr/bin/env bats
# The workbench command: help, errors that say what to do, attach from a subfolder and
# the hint for projects that run in a devcontainer.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  make_sandbox
  export BASE="$SANDBOX/my-workbench"
  bootstrap "$BASE" --repo "$PRIVATE"
}

@test "workbench help перечисляет команды" {
  run -0 "$SANDBOX/bin/workbench" help
  [[ $output == *attach* ]]
  [[ $output == *detach* ]]
  [[ $output == *"attach --user"* ]]
  [[ $output == *"detach --user"* ]]
}

@test "неизвестная команда - понятная ошибка" {
  run -1 "$SANDBOX/bin/workbench" frobnicate
  [[ $output == *frobnicate* ]]
}

@test "подключение из подпапки проекта подключает его корень" {
  new_project "$SANDBOX/p-sub"
  mkdir "$SANDBOX/p-sub/src"
  wb "$SANDBOX/p-sub/src" attach
  [ -L "$SANDBOX/p-sub/.workbench" ]
  [ ! -e "$SANDBOX/p-sub/src/.workbench" ]
}

@test "подключение вне git-проекта - понятная ошибка" {
  mkdir "$SANDBOX/not-a-project"
  run -1 wb "$SANDBOX/not-a-project" attach
  [[ $output == *git* ]]
}

@test "базу не подключают к самой себе" {
  run -1 wb "$BASE" attach
  [ ! -e "$BASE/.workbench" ]
}

@test "папка .workbench со старой копией базы не затирается" {
  new_project "$SANDBOX/p-old"
  mkdir "$SANDBOX/p-old/.workbench"
  printf 'x\n' >"$SANDBOX/p-old/.workbench/file"
  run -1 wb "$SANDBOX/p-old" attach
  [ -f "$SANDBOX/p-old/.workbench/file" ]
  [[ $output == *.workbench* ]]
}

@test "подключение проекта без инструкций базы на уровне пользователя подсказывает attach --user" {
  new_project "$SANDBOX/p-imports"
  run -0 wb "$SANDBOX/p-imports" attach
  [[ $output == *"workbench attach --user"* ]]
  [[ $output != *"allow external imports"* ]]
}

@test "в проекте с контейнером подсказывает, как смонтировать базу и подключить её инструкции в контейнере" {
  new_project "$SANDBOX/p-dc"
  mkdir "$SANDBOX/p-dc/.devcontainer"
  printf '{}\n' >"$SANDBOX/p-dc/.devcontainer/devcontainer.json"
  run -0 wb "$SANDBOX/p-dc" attach
  [[ $output == *"\"source\": \"$BASE\", \"target\": \"$BASE\""* ]]
  [[ $output == *"sh \"$BASE/bin/workbench\" attach --user"* ]]
}
