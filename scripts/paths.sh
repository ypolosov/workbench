#!/bin/sh
# Shared definitions for workbench scripts and hooks. POSIX sh gives a sourced file no
# way to find itself, so the sourcing script sets WB_DIR (the root of the personal base)
# from its own location first, then sources this file.
# FPF_DIR:  the pinned FPF worktree inside the base.
# OVERLAY:  optional personal Claude Code settings merged into generated ones.
# MERGE_JQ: jq program merging two JSON documents .[0] and .[1]: objects
#           recursively, arrays concatenated without duplicates, other values from .[1].

: "${WB_DIR:?set WB_DIR before sourcing paths.sh}"
# The variables below are read by the scripts and hooks that source this file.
# shellcheck disable=SC2034
FPF_DIR="$WB_DIR/.fpf"
# shellcheck disable=SC2034
OVERLAY="$WB_DIR/adapters/claude/settings.overlay.json"
# jq variables, not shell ones.
# shellcheck disable=SC2016,SC2034
MERGE_JQ='
  def m($a; $b): reduce ($b | keys_unsorted[]) as $k ($a;
    .[$k] = (if ($a[$k] | type) == "object" and ($b[$k] | type) == "object" then m($a[$k]; $b[$k])
             elif ($a[$k] | type) == "array" and ($b[$k] | type) == "array" then ($a[$k] + $b[$k] | unique)
             else $b[$k] end));
  m(.[0]; .[1])'

# Prints a value from .fpf-edition (key=value lines).
wb_fpf_edition() {
  sed -n "s/^$1=//p" "$WB_DIR/.fpf-edition" | tail -n 1
}

# Prints the Claude Code hooks of the adapter. $1 is the hooks directory the way the
# hook commands name it, e.g. '$CLAUDE_PROJECT_DIR/.workbench/adapters/claude/hooks'.
wb_hooks_json() {
  jq -n --arg h "$1" '
    def cmd(name): {type: "command", command: ("\"" + $h + "/" + name + "\"")};
    {
      hooks: {
        SessionStart: [{hooks: [cmd("session-start.sh")]}],
        UserPromptSubmit: [{hooks: [cmd("wp-gate-reminder.sh"), cmd("close-gate-reminder.sh")]}],
        PreToolUse: [{matcher: "Bash", hooks: [cmd("destructive-guard.sh")]}]
      }
    }'
}

# Prints the JSON document $1 merged with the personal overlay, when there is one.
wb_with_overlay() {
  if [ -f "$OVERLAY" ]; then
    printf '%s' "$1" | jq -s "$MERGE_JQ" - "$OVERLAY"
  else
    printf '%s\n' "$1"
  fi
}

# True under Git Bash, MSYS2 or Cygwin on Windows, where a link to a folder is a
# junction: it needs no administrator rights, and git and editors follow it.
wb_windows() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) return 0 ;;
  esac
  return 1
}

# wb_cmd <args...>: runs cmd.exe with its switches (/c, /J) passed as they are: Git Bash
# and MSYS2 would otherwise rewrite them as paths.
wb_cmd() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' cmd "$@"
}

# wb_link <target> <link>: a link to a folder; a relative target counts from the
# link's own folder.
wb_link() {
  if wb_windows; then
    wb_target="$(cd "$(dirname "$2")" && cd "$1" && pwd -P)"
    wb_cmd /c mklink /J "$(cygpath -w "$2")" "$(cygpath -w "$wb_target")" >/dev/null
  else
    ln -s "$1" "$2"
  fi
}

# wb_unlink <link>: removes the link only, never the folder it points to.
wb_unlink() {
  if wb_windows; then
    wb_cmd /c rmdir "$(cygpath -w "$1")" >/dev/null
  else
    rm -f "$1"
  fi
}

wb_native_path() {
  if wb_windows; then
    cygpath -m "$1"
  else
    printf '%s\n' "$1"
  fi
}

wb_import() {
  printf '@%s\n' "$(wb_native_path "$1")" | sed 's/ /\\ /g'
}

wb_user_claude_md() {
  printf '%s/CLAUDE.md\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
}

wb_user_attached() {
  grep -qxF "$(wb_import "$WB_DIR/AGENTS.md")" "$(wb_user_claude_md)" 2>/dev/null
}
