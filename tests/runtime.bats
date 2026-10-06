#!/usr/bin/env bats
# One mounted base can serve different homes (WSL and a devcontainer).
bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  make_sandbox
}

@test "общая база находит инструменты текущего пользователя после установки в другом окружении" {
  second_home="$SANDBOX/second home"
  mkdir -p "$second_home/.local/bin" "$second_home/bin"
  printf '#!/bin/sh\nexit 0\n' >"$second_home/.local/bin/jq"
  printf '#!/bin/sh\nexit 0\n' >"$second_home/bin/codex"
  chmod +x "$second_home/.local/bin/jq" "$second_home/bin/codex"
  # Load the real generated launch environment just as bin/workbench does.
  cat >"$SANDBOX/second-home.sh" <<'PROBE'
#!/bin/sh
set -eu
WB_DIR=$1
. "$WB_DIR/scripts/paths.sh"
. "$WB_DIR/scripts/runtime.sh"
wb_runtime_install "$HOME/bin"
HOME=$2
export HOME
. "$WB_DIR/.runtime/env.sh"
command -v jq
command -v codex
PROBE
  run -0 sh "$SANDBOX/second-home.sh" "$TPL" "$second_home"
  [ "${lines[0]}" = "$second_home/.local/bin/jq" ]
  [ "${lines[1]}" = "$second_home/bin/codex" ]
}

@test "update общей базы устанавливает команду в домашнюю папку текущего пользователя" {
  base="$SANDBOX/shared base"
  bootstrap "$base" --local
  mkdir -p "$base/.runtime"
  jq -n --arg bin "$HOME/.local/bin" '{binDir: $bin}' >"$base/.runtime/install.json"
  second_home="$SANDBOX/second installer home"
  mkdir -p "$second_home"
  run -0 env HOME="$second_home" sh "$base/bin/workbench" update --template "$TPL" --yes --core-only
  [ -f "$second_home/.local/bin/workbench" ]
}
