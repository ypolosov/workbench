#!/bin/sh
# Shared definitions for workbench scripts and hooks. POSIX sh gives a sourced file no
# way to find itself, so the sourcing script sets WB_DIR (the root of this workbench
# clone) from its own location first, then sources this file.
# FPF_DIR:  the pinned FPF worktree inside the clone.
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

# Prints the project that hosts this clone as <project>/.workbench; fails otherwise.
wb_host_project() {
  [ "$(basename "$WB_DIR")" = ".workbench" ] || return 1
  wb_parent="$(dirname "$WB_DIR")"
  git -C "$wb_parent" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  printf '%s\n' "$wb_parent"
}

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
