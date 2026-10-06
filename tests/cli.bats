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

@test "подсказка attach --user называет только агентов, у которых блока нет" {
  new_project "$SANDBOX/p-half"
  (
    export CLAUDE_CONFIG_DIR="$SANDBOX/claude-half" CODEX_HOME="$SANDBOX/codex-half"
    wb "$SANDBOX/p-half" attach --user
    rm "$CODEX_HOME/AGENTS.md"
    run -0 wb "$SANDBOX/p-half" attach
    [[ $output == *"Codex ($CODEX_HOME/AGENTS.md)"* ]]
    [[ $output != *"Claude Code ("* ]]
    [[ $output == *"workbench attach --user"* ]]
  )
}

@test "в проекте, где контейнер уже монтирует базу по тому же пути, подсказки о контейнере нет" {
  new_project "$SANDBOX/p-dc-mounted"
  mkdir "$SANDBOX/p-dc-mounted/.devcontainer"
  {
    printf '{\n  // the personal base, at the same path\n  "mounts": [\n    {\n'
    # A devcontainer variable, not shell text.
    # shellcheck disable=SC2016
    printf '      "source": "${localEnv:HOME}/elsewhere",\n      "target": "%s",\n' "$BASE"
    printf '      "type": "bind"\n    },\n  ],\n}\n'
  } >"$SANDBOX/p-dc-mounted/.devcontainer/devcontainer.json"
  run -0 wb "$SANDBOX/p-dc-mounted" attach
  [[ $output != *"в контейнере база видна"* ]]
}

@test "монтирование базы строкой тоже гасит подсказку о контейнере" {
  new_project "$SANDBOX/p-dc-string"
  mkdir "$SANDBOX/p-dc-string/.devcontainer"
  printf '{"mounts": ["source=/somewhere,target=%s,type=bind"]}\n' "$BASE" \
    >"$SANDBOX/p-dc-string/.devcontainer/devcontainer.json"
  run -0 wb "$SANDBOX/p-dc-string" attach
  [[ $output != *"в контейнере база видна"* ]]
}

@test "монтирование в соседнюю папку подсказку о контейнере не гасит" {
  new_project "$SANDBOX/p-dc-other"
  mkdir "$SANDBOX/p-dc-other/.devcontainer"
  printf '{"mounts": [{"source": "%s", "target": "%s-other", "type": "bind"}]}\n' "$BASE" "$BASE" \
    >"$SANDBOX/p-dc-other/.devcontainer/devcontainer.json"
  run -0 wb "$SANDBOX/p-dc-other" attach
  [[ $output == *"в контейнере база видна"* ]]
}

@test "workbench.cmd лежит рядом с командой и хранится с концами строк CRLF, как ждёт cmd.exe" {
  [ -f "$BASE/bin/workbench.cmd" ]
  [ "$(git -C "$BASE" check-attr eol -- bin/workbench.cmd)" = "bin/workbench.cmd: eol: crlf" ]
  grep -q 'bin\\sh.exe' "$BASE/bin/workbench.cmd"
}

@test "workbench.cmd из cmd.exe: справка и подключение проекта" {
  if ! on_windows; then skip "только Windows"; fi
  new_project "$SANDBOX/p-cmd"
  cmd_file="$(cygpath -w "$BASE/bin/workbench.cmd")"
  run -0 cmd //c "$cmd_file" help
  [[ $output == *"attach --user"* ]]
  (cd "$SANDBOX/p-cmd" && cmd //c "$cmd_file" attach)
  [ -f "$SANDBOX/p-cmd/.workbench/AGENTS.md" ]
  run -1 cmd //c "$cmd_file" frobnicate
}
