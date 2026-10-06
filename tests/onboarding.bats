#!/usr/bin/env bats
# Full installation leaves a usable command, user instructions, project integration
# and a machine-readable diagnostic result. Every case stays in the offline sandbox.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  make_sandbox
  export BASE="$SANDBOX/local base" WORKBENCH_PATH_STORE="$SANDBOX/windows-path.txt"
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  new_project "$SANDBOX/project with spaces"
  # The vendor boundary is simulated; base, git, profiles, links and hook commands are real.
  mkdir "$SANDBOX/vendor"
  cat >"$SANDBOX/vendor/codex" <<'VENDOR'
#!/bin/sh
[ "$1" = app-server ] || { printf 'codex-cli test\n'; exit 0; }
while IFS= read -r request; do
  method="$(printf '%s' "$request" | jq -r '.method')"
  case $method in
    initialize) printf '%s\n' '{"id":1,"result":{}}' ;;
    hooks/list)
      status=untrusted
      [ ! -f "$HOME/codex-edits.jsonl" ] || status=trusted
      printf '%s' "$request" | jq -c --arg status "$status" '{id: 2, result: {data: [.params.cwds[] as $cwd | {
        cwd: $cwd, hooks: ["session-start.sh", "wp-gate-reminder.sh", "close-gate-reminder.sh", "destructive-guard.sh"] |
          map({key: ($cwd + "/.codex/hooks.json:" + .), eventName: "test", handlerType: "command",
            command: ("workbench.cmd --hook " + .), sourcePath: ($cwd + "/.codex/hooks.json"),
            currentHash: ("sha256:" + ("0" * 64)), enabled: true, trustStatus: $status})
      }]}}'
      ;;
    config/batchWrite)
      printf '%s\n' "$request" >>"$HOME/codex-edits.jsonl"
      printf '%s\n' '{"id":2,"result":{}}'
      ;;
  esac
done
VENDOR
  chmod +x "$SANDBOX/vendor/codex"
  export PATH="$SANDBOX/vendor:$PATH"

}

@test "одна установка создаёт локальную базу и полностью подключает текущий проект" {
  run -0 sh "$TPL/install.sh" --template "$TPL" --local --yes --dir "$BASE" \
    --bin-dir "$SANDBOX/bin" --project "$SANDBOX/project with spaces" --no-launch
  [ -f "$BASE/.runtime/install.json" ]
  [ -f "$HOME/.claude/CLAUDE.md" ]
  [ -f "$HOME/.codex/AGENTS.md" ]
  [ -f "$SANDBOX/project with spaces/.workbench/AGENTS.md" ]
  [ -f "$BASE/.runtime/doctor.json" ]
  jq -e '.ready == true' "$BASE/.runtime/doctor.json"
}

@test "doctor доступен независимо от текущей папки и выдаёт понятный JSON" {
  run -0 "$SANDBOX/bin/workbench" doctor --json --project "$SANDBOX/project with spaces"
  printf '%s' "$output" | jq -e '.ready == true and ([.checks[].id] | index("guard") != null)'
}

@test "повторная установка находит существующий workbench и сохраняет личные материалы и правки" {
  printf 'owner memory\n' >"$BASE/memory/owner.md"
  printf '# owner custom hook\n' >>"$BASE/scripts/hooks.sh"
  printf '# updated doctor\n' >>"$TPL/scripts/doctor.sh"
  printf 'template memory must not replace owner data\n' >"$TPL/memory/owner.md"
  git -C "$TPL" add scripts/doctor.sh memory/owner.md
  git -C "$TPL" commit -qm "new program snapshot"
  run -0 env PATH="$BASE/bin:$PATH" sh "$TPL/install.sh" --template "$TPL" --yes \
    --bin-dir "$SANDBOX/bin" --project "$SANDBOX/project with spaces" --no-launch
  [ ! -d "$HOME/my-workbench" ]
  [ "$(cat "$BASE/memory/owner.md")" = 'owner memory' ]
  grep -q '^# owner custom hook$' "$BASE/scripts/hooks.sh"
  grep -q '^# updated doctor$' "$BASE/scripts/doctor.sh"
}

@test "установщик находит личный workbench по инструкциям даже без рабочей команды в PATH" {
  printf '#!/bin/sh\nexit 127\n' >"$SANDBOX/vendor/workbench"
  chmod +x "$SANDBOX/vendor/workbench"
  run -0 sh "$TPL/install.sh" --template "$TPL" --yes --bin-dir "$SANDBOX/bin" --no-launch
  [ ! -d "$HOME/my-workbench" ]
  [ "$(cat "$BASE/memory/owner.md")" = 'owner memory' ]
}

@test "doctor находит сломанное подключение проекта" {
  wb "$SANDBOX/project with spaces" detach
  run -1 "$SANDBOX/bin/workbench" doctor --json --project "$SANDBOX/project with spaces"
  printf '%s' "$output" | jq -e '.ready == false and any(.checks[]; .id == "project" and .status == "error")'
}

@test "doctor без параметров проверяет последнее подключение, включая его поломку" {
  run -1 "$SANDBOX/bin/workbench" doctor --json
  printf '%s' "$output" | jq -e '.ready == false and any(.checks[]; .id == "project" and .status == "error")'
}

@test "загрузчик Windows ставит workbench без Git и jq в исходном PATH" {
  on_windows || skip "только Windows"
  [ "${WORKBENCH_TEST_COLD_WINDOWS:-0}" = 1 ] || skip "холодная загрузка: WORKBENCH_TEST_COLD_WINDOWS=1"
  cat >"$SANDBOX/cold.ps1" <<'BOOT'
param($Installer,$Template,$Base,$Bin,$Project,$HomeDir,$Store)
$ErrorActionPreference='Stop'
$env:HOME=$HomeDir
$env:USERPROFILE=$HomeDir
$env:LOCALAPPDATA=Join-Path $HomeDir 'AppData\Local'
$env:WORKBENCH_TOOLS_BIN=Join-Path $HomeDir 'tools\bin'
Remove-Item Env:CLAUDE_CODE_GIT_BASH_PATH -ErrorAction SilentlyContinue
$env:Path=$env:SystemRoot+'\System32;'+$env:SystemRoot+'\System32\WindowsPowerShell\v1.0'
& $Installer -Template $Template -Dir $Base -BinDir $Bin -Project $Project -PathStore $Store -Local -Yes -NoLaunch
if (-not (Test-Path -LiteralPath (Join-Path $Base '.runtime\doctor.json'))) { throw 'doctor report missing' }
$report=Get-Content -LiteralPath (Join-Path $Base '.runtime\doctor.json') -Raw | ConvertFrom-Json
if (-not $report.ready) { throw 'installation not ready' }
$savedEnvironment=Get-Content -LiteralPath ($Store+'.environment.json') -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $savedEnvironment.CLAUDE_CODE_GIT_BASH_PATH)) { throw 'Claude Bash environment missing' }
& $env:ComSpec /d /c 'where.exe workbench && where.exe jq && workbench help && workbench doctor --json'
if ($LASTEXITCODE -ne 0) { throw 'fresh cmd cannot use workbench' }
& workbench doctor --json
if ($LASTEXITCODE -ne 0) { throw 'PowerShell cannot use workbench' }
& $env:WORKBENCH_GIT_SH -l -c 'command -v workbench && workbench doctor --json'
if ($LASTEXITCODE -ne 0) { throw 'fresh Git Bash cannot use workbench' }
BOOT
  run -0 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(native "$SANDBOX/cold.ps1")" \
    -Installer "$(native "$TPL/install.ps1")" -Template "$(native "$TPL")" \
    -Base "$(native "$SANDBOX/cold base")" -Bin "$(native "$SANDBOX/cold bin")" \
    -Project "$(native "$SANDBOX/project with spaces")" -HomeDir "$(native "$SANDBOX/cold home")" \
    -Store "$(native "$SANDBOX/cold-path.txt")"
}

@test "загрузчик Linux ставит workbench в чистом контейнере без Git и jq" {
  [ "$(uname -s)" = Linux ] || skip "только Linux"
  [ "${WORKBENCH_TEST_COLD_LINUX:-0}" = 1 ] || skip "холодная загрузка: WORKBENCH_TEST_COLD_LINUX=1"
  run -0 docker run --rm -i --mount "type=bind,src=$SANDBOX,dst=/test-fixture,readonly" \
    debian:bookworm-slim sh -s -- "$SANDBOX" <"$ROOT/tests/cold-linux.sh"
}

@test "конфликт обновления программы сохраняет файлы владельца и не применяет часть обновления" {
  printf '# owner doctor edit\n' >>"$BASE/scripts/doctor.sh"
  cp "$BASE/scripts/doctor.sh" "$SANDBOX/doctor-before"
  printf '# conflicting upstream edit\n' >>"$TPL/scripts/doctor.sh"
  printf '# pending tool change\n' >>"$TPL/scripts/install-tools.sh"
  git -C "$TPL" add scripts/doctor.sh scripts/install-tools.sh
  git -C "$TPL" commit -qm "published conflicting update"
  run -1 sh "$TPL/install.sh" --template "$TPL" --yes --dir "$BASE" \
    --bin-dir "$SANDBOX/bin" --no-launch
  cmp "$BASE/scripts/doctor.sh" "$SANDBOX/doctor-before"
  run -1 grep -q '^# pending tool change$' "$BASE/scripts/install-tools.sh"
}

@test "каталог зависимостей в формате Windows работает в PATH оболочки sh" {
  on_windows || skip "только Windows"
  mkdir -p "$SANDBOX/cached tools"
  printf '#!/bin/sh\nprintf "cached-jq\\n"\n' >"$SANDBOX/cached tools/jq"
  chmod +x "$SANDBOX/cached tools/jq"
  cat >"$SANDBOX/tools-probe.sh" <<'PROBE'
#!/bin/sh
WB_DIR="$(cygpath -u "$1")"
. "$WB_DIR/scripts/install-tools.sh"
command -v jq && wb_install_tool jq && sh -c 'jq --version'
PROBE
  cat >"$SANDBOX/tools-probe.ps1" <<'BRIDGE'
param($GitSh,$Probe,$Template,$Tools)
$env:WORKBENCH_TOOLS_BIN=$Tools
$env:Path=$env:SystemRoot+'\System32;'+$env:SystemRoot+'\System32\WindowsPowerShell\v1.0'
& $GitSh $Probe $Template
exit $LASTEXITCODE
BRIDGE
  run -0 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(native "$SANDBOX/tools-probe.ps1")" \
    -GitSh "$(cygpath -w "$(cygpath -m /)/bin/sh.exe")" -Probe "$(native "$SANDBOX/tools-probe.sh")" \
    -Template "$(native "$TPL")" -Tools "$(cygpath -w "$SANDBOX/cached tools")"
  [[ $output == *cached-jq* ]]
}

@test "обновление программы не считает окончания строк Windows местной правкой" {
  eol_base="$SANDBOX/eol base"
  eol_template="$SANDBOX/eol template"
  git clone -q "$TPL" "$eol_template"
  git clone -q "$eol_template" "$eol_base"
  git -C "$eol_base" diff --quiet HEAD -- bin/workbench.cmd
  printf 'rem updated launcher\r\n' >>"$eol_template/bin/workbench.cmd"
  git -C "$eol_template" add bin/workbench.cmd
  git -C "$eol_template" commit -qm "published launcher update"
  # shellcheck disable=SC2016
  run -0 sh -c 'WB_DIR=$1; . "$2/scripts/upgrade.sh"; wb_upgrade_program "$2"' sh "$eol_base" "$eol_template"
  cmp "$eol_base/bin/workbench.cmd" "$eol_template/bin/workbench.cmd"
  git -C "$eol_base" diff --quiet HEAD -- bin/workbench.cmd
}
