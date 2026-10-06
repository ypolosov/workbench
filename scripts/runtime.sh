#!/bin/sh
# Machine-local launch environment; caller defines WB_DIR and loads paths.sh.
wb_quote_sh() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

wb_runtime_install() {
  wb_bin_dir=$1
  wb_tools_bin=${WORKBENCH_TOOLS_BIN:-$HOME/.cache/workbench/tools/bin}
  if wb_windows; then wb_tools_bin="$(cygpath -u "$wb_tools_bin")"; fi
  mkdir -p "$WB_DIR/.runtime"
  wb_runtime_prefix="$WB_DIR/bin:$wb_bin_dir:$wb_tools_bin:$HOME/bin"
  # A dependency found in a nonstandard directory must remain visible in new shells.
  wb_jq_bin="$(dirname "$(command -v jq)")"
  case ":$wb_runtime_prefix:" in *":$wb_jq_bin:"*) ;; *) wb_runtime_prefix="$wb_runtime_prefix:$wb_jq_bin" ;; esac
  if wb_windows; then
    wb_sh_native=${WORKBENCH_GIT_SH:-$(cygpath -w "$(cygpath -m /)/bin/sh.exe")}
    wb_git_cmd="$(dirname "$(cygpath -u "$wb_sh_native")")/../cmd"
    wb_bash_native="$(cygpath -w "$(dirname "$(cygpath -u "$wb_sh_native")")/bash.exe")"
    if [ ! -f "${CLAUDE_CODE_GIT_BASH_PATH:-}" ]; then CLAUDE_CODE_GIT_BASH_PATH=$wb_bash_native; fi
    export CLAUDE_CODE_GIT_BASH_PATH
    wb_runtime_prefix="$wb_runtime_prefix:$wb_git_cmd"
  fi
  # Expanded by the future shell, not by the installer.
  # shellcheck disable=SC2016
  printf 'export PATH="$WB_DIR/bin:$HOME/.local/bin:$HOME/bin:$HOME/.cache/workbench/tools/bin":%s:"$PATH"\n' \
    "$(wb_quote_sh "$wb_runtime_prefix")" >"$WB_DIR/.runtime/env.sh"
  if wb_windows; then
    printf 'export CLAUDE_CODE_GIT_BASH_PATH=%s\n' "$(wb_quote_sh "$CLAUDE_CODE_GIT_BASH_PATH")" >>"$WB_DIR/.runtime/env.sh"
  fi
  if wb_windows; then
    wb_native_prefix="$(cygpath -wp "$wb_runtime_prefix")"
    # Percent signs in a literal batch-file value need doubling.
    wb_native_prefix="$(printf '%s' "$wb_native_prefix" | sed 's/%/%%/g')"
    wb_sh_native="$(printf '%s' "$wb_sh_native" | sed 's/%/%%/g')"
    wb_bash_batch="$(printf '%s' "$CLAUDE_CODE_GIT_BASH_PATH" | sed 's/%/%%/g')"
    printf '@echo off\r\nset "WB_SH=%s"\r\nset "PATH=%s;%%PATH%%"\r\nset "CLAUDE_CODE_GIT_BASH_PATH=%s"\r\n' \
      "$wb_sh_native" "$wb_native_prefix" "$wb_bash_batch" >"$WB_DIR/.runtime/env.cmd"
  fi
  PATH="$wb_runtime_prefix:$PATH"
  export PATH
}

wb_profile_block() {
  wb_profile=$1
  wb_profile_dir="$(dirname "$wb_profile")"
  mkdir -p "$wb_profile_dir"
  [ -e "$wb_profile" ] || : >"$wb_profile"
  awk '
    /^# workbench:environment begin$/ {skip=1; next}
    /^# workbench:environment end$/ {skip=0; next}
    !skip {print}
  ' "$wb_profile" >"$WB_DIR/.runtime/profile.tmp"
  cat "$WB_DIR/.runtime/profile.tmp" >"$wb_profile"
  {
    printf '\n# workbench:environment begin\n'
    # shellcheck disable=SC2016
    printf 'export PATH=%s:"$PATH"\n' "$(wb_quote_sh "$wb_runtime_prefix")"
    printf '# workbench:environment end\n'
  } >>"$wb_profile"
  rm -f "$WB_DIR/.runtime/profile.tmp"
}

wb_runtime_persist() {
  if wb_windows; then
    wb_path_store=""
    [ -z "${WORKBENCH_PATH_STORE:-}" ] || wb_path_store="$(wb_native_path "$WORKBENCH_PATH_STORE")"
    jq -n --arg bins "$(cygpath -wp "$wb_runtime_prefix")" \
      --arg store "$wb_path_store" --arg bash "$CLAUDE_CODE_GIT_BASH_PATH" \
      '{bins: $bins, store: $store, variables: {CLAUDE_CODE_GIT_BASH_PATH: $bash}}' >"$WB_DIR/.runtime/path-plan.json"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wb_native_path "$WB_DIR/scripts/windows-env.ps1")" \
      -Plan "$(wb_native_path "$WB_DIR/.runtime/path-plan.json")" >/dev/null
  else
    wb_profile_block "$HOME/.profile"
    wb_profile_block "$HOME/.bashrc"
    # A user's existing bash login profile may shadow .profile.
    for wb_login_profile in "$HOME/.bash_profile" "$HOME/.bash_login"; do
      [ ! -e "$wb_login_profile" ] || wb_profile_block "$wb_login_profile"
    done
    wb_profile_block "${ZDOTDIR:-$HOME}/.zshenv"
  fi
}

# A file-backed provider keeps Windows tests off the owner's HKCU environment.
wb_runtime_command_ready() {
  command -v workbench >/dev/null 2>&1 || command -v workbench.cmd >/dev/null 2>&1
}
