#!/bin/sh
# Verified user-local dependencies. No Node, Python or Go runtime is required.
wb_tools_bin=${WORKBENCH_TOOLS_BIN:-$HOME/.cache/workbench/tools/bin}
if command -v cygpath >/dev/null 2>&1; then wb_tools_bin="$(cygpath -u "$wb_tools_bin")"; fi
PATH="$wb_tools_bin:$PATH"
export PATH
wb_download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 2 --connect-timeout 20 -sS "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$1" -O "$2"
  else
    printf 'workbench: загрузка недоступна: нет curl или wget\n' >&2
    return 1
  fi
}
wb_checksum() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else openssl dgst -sha256 "$1" | awk '{print $NF}'; fi
}
wb_tool_platform() {
  case "$(uname -s)" in
    Darwin) wb_os=macos ;;
    Linux) wb_os=linux ;;
    MINGW* | MSYS* | CYGWIN*) wb_os=windows ;;
    *)
      printf 'workbench: эта ОС пока не поддерживается\n' >&2
      return 1
      ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) wb_arch=amd64 ;;
    aarch64 | arm64) wb_arch=arm64 ;;
    *)
      printf 'workbench: эта архитектура пока не поддерживается\n' >&2
      return 1
      ;;
  esac
}
wb_install_tool() {
  wb_tool_name=$1
  if command -v "$wb_tool_name" >/dev/null 2>&1 &&
    sh -c '"$1" --version' sh "$wb_tool_name" >/dev/null 2>&1; then return 0; fi
  wb_tool_platform || return 1
  # Gum supplies an x64 Windows binary; Windows on ARM runs it through emulation.
  if [ "$wb_tool_name:$wb_os" = gum:windows ]; then wb_arch=amd64; fi
  wb_tool_row="$(awk -F '|' -v key="$wb_tool_name-$wb_os-$wb_arch" '$1 == key {print; exit}' "$WB_DIR/scripts/tools.lock")"
  [ -n "$wb_tool_row" ] || return 1
  wb_tool_url="$(printf '%s' "$wb_tool_row" | cut -d '|' -f 2)"
  wb_tool_hash="$(printf '%s' "$wb_tool_row" | cut -d '|' -f 3)"
  wb_tool_kind="$(printf '%s' "$wb_tool_row" | cut -d '|' -f 4)"
  mkdir -p "$wb_tools_bin"
  wb_tool_stage="$(mktemp -d "${TMPDIR:-/tmp}/workbench-tool.XXXXXX")"
  wb_download "$wb_tool_url" "$wb_tool_stage/download" || return 1
  [ "$(wb_checksum "$wb_tool_stage/download")" = "$wb_tool_hash" ] || {
    printf 'workbench: контрольная сумма %s не совпала\n' "$wb_tool_name" >&2
    return 1
  }
  wb_tool_suffix=""
  [ "$wb_os" != windows ] || wb_tool_suffix=.exe
  case $wb_tool_kind in
    raw) cp "$wb_tool_stage/download" "$wb_tools_bin/$wb_tool_name$wb_tool_suffix" ;;
    tgz)
      tar -xzf "$wb_tool_stage/download" -C "$wb_tool_stage"
      wb_tool_file="$(find "$wb_tool_stage" -type f -name "$wb_tool_name" | head -n 1)"
      [ -n "$wb_tool_file" ] || return 1
      cp "$wb_tool_file" "$wb_tools_bin/$wb_tool_name"
      ;;
    zip)
      unzip -q "$wb_tool_stage/download" -d "$wb_tool_stage"
      wb_tool_file="$(find "$wb_tool_stage" -type f -name "$wb_tool_name.exe" | head -n 1)"
      [ -n "$wb_tool_file" ] || return 1
      cp "$wb_tool_file" "$wb_tools_bin/$wb_tool_name.exe"
      ;;
    *) return 1 ;;
  esac
  chmod +x "$wb_tools_bin/$wb_tool_name$wb_tool_suffix"
  PATH="$wb_tools_bin:$PATH"
  export PATH
  sh -c '"$1" --version' sh "$wb_tool_name" >/dev/null
}
