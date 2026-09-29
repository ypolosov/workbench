#!/usr/bin/env bash
# Connects this workbench clone to the project that hosts it as <project>/.workbench.
# Nothing is committed into the project: every file created there is listed in the
# project's .git/info/exclude and recorded in a state file inside its git dir.
# Links and settings use paths relative to the project, so the same files work on
# any machine and inside a devcontainer.
#
# Usage: attach.sh [<project-dir>]            connect (default: the hosting project)
#        attach.sh --detach [<project-dir>]   remove exactly what attach created
set -euo pipefail

# shellcheck source=paths.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/paths.sh"

MARK="workbench:attach"
# Expanded by the shell that runs each hook, not here.
# shellcheck disable=SC2016
HOOKS='$CLAUDE_PROJECT_DIR/.workbench/adapters/claude/hooks'

die() {
  echo "attach: $*" >&2
  exit 1
}

# Sets TARGET, STATE and EXCLUDE; the project must host this clone as .workbench.
use_target() {
  local dir="$1" git_dir
  if [ -z "$dir" ]; then
    dir="$(wb_host_project)" || die "clone workbench into <project>/.workbench first"
  fi
  TARGET="$(cd "$dir" 2>/dev/null && pwd -P)" || die "no such directory: $dir"
  [ "$TARGET/.workbench" -ef "$WB_DIR" ] || die "this clone is not $TARGET/.workbench"
  git_dir="$(git -C "$TARGET" rev-parse --absolute-git-dir 2>/dev/null)" || die "not a git repository: $TARGET"
  STATE="$git_dir/workbench-attach.state"
  EXCLUDE="$git_dir/info/exclude"
}

record() {
  echo "$1 $2" >>"$STATE"
}

# The clone itself stays excluded while it exists, even after --detach.
exclude_clone() {
  mkdir -p "$(dirname "$EXCLUDE")"
  if ! grep -qxF '/.workbench/' "$EXCLUDE" 2>/dev/null; then
    printf '# workbench clone: personal, never commit\n/.workbench/\n' >>"$EXCLUDE"
  fi
}

write_claude_local() {
  local file="$TARGET/CLAUDE.local.md"
  if [ -e "$file" ] && ! grep -q "$MARK" "$file"; then
    die "CLAUDE.local.md exists and was not created by workbench: $file"
  fi
  cat >"$file" <<EOF
<!-- $MARK: local file, never commit it. Remove with: .workbench/scripts/attach.sh --detach -->
# Подключён workbench

- \$WORKBENCH = .workbench (клон личного workbench)
- \$FPF = .workbench/.fpf (закреплённое издание FPF)

@.workbench/AGENTS.md
EOF
  record created CLAUDE.local.md
}

# Hooks of the Claude Code adapter plus the owner's optional overlay.
settings_json() {
  local base
  base="$(jq -n --arg h "$HOOKS" '
    def cmd(name): {type: "command", command: ("\"" + $h + "/" + name + "\"")};
    {
      hooks: {
        SessionStart: [{hooks: [cmd("session-start.sh")]}],
        UserPromptSubmit: [{hooks: [cmd("wp-gate-reminder.sh"), cmd("close-gate-reminder.sh")]}],
        PreToolUse: [{matcher: "Bash", hooks: [cmd("destructive-guard.sh")]}]
      }
    }')"
  wb_with_overlay "$base"
}

# Creates .claude/settings.local.json, or merges into an existing one after a backup.
write_settings() {
  local file="$TARGET/.claude/settings.local.json" ours
  if [ ! -d "$TARGET/.claude" ]; then
    mkdir "$TARGET/.claude"
    record created-dir .claude
  fi
  ours="$(settings_json)"
  if [ -f "$file" ]; then
    cp "$file" "$file.wb-backup"
    record backup .claude/settings.local.json
    # Merge into a temporary file: the project's own file changes only on success.
    if ! printf '%s' "$ours" | jq -s "$MERGE_JQ" "$file.wb-backup" - >"$file.wb-tmp"; then
      rm -f "$file.wb-tmp"
      die "cannot merge into $file (left unchanged; run --detach to clean up)"
    fi
    mv "$file.wb-tmp" "$file"
  else
    printf '%s\n' "$ours" >"$file"
    record created .claude/settings.local.json
  fi
}

link_skills() {
  local skill name link
  if [ ! -d "$TARGET/.claude/skills" ]; then
    mkdir "$TARGET/.claude/skills"
    record created-dir .claude/skills
  fi
  for skill in "$WB_DIR"/.agents/skills/*/; do
    name="$(basename "$skill")"
    link="$TARGET/.claude/skills/$name"
    if [ -e "$link" ] || [ -L "$link" ]; then
      echo "attach: skill $name already exists in the project, skipped" >&2
      continue
    fi
    ln -s "../../.workbench/.agents/skills/$name" "$link"
    record created ".claude/skills/$name"
  done
}

write_exclude() {
  {
    echo "# $MARK begin"
    sed -n 's/^\(created\|created-dir\|backup\) //p' "$STATE" | sed 's#^#/#'
    if grep -q '^backup ' "$STATE"; then echo "/.claude/settings.local.json.wb-backup"; fi
    echo "# $MARK end"
  } >>"$EXCLUDE"
}

attach() {
  [ -d "$FPF_DIR" ] || die "FPF edition is not prepared: run .workbench/scripts/setup.sh"
  : >"$STATE"
  exclude_clone
  write_claude_local
  write_settings
  link_skills
  write_exclude
  echo "attached: $TARGET"
}

detach() {
  [ -f "$STATE" ] || die "workbench is not attached to $TARGET"
  local kind rel
  # Undo in reverse order: files and links first, then the directories that held them.
  awk '{ lines[NR] = $0 } END { for (i = NR; i > 0; i--) print lines[i] }' "$STATE" |
    while read -r kind rel; do
      case "$kind" in
        created) rm -f "${TARGET:?}/$rel" ;;
        backup) mv -f "$TARGET/$rel.wb-backup" "$TARGET/$rel" ;;
        created-dir) rmdir "$TARGET/$rel" 2>/dev/null || echo "attach: kept non-empty $rel" >&2 ;;
      esac
    done
  sed "/^# $MARK begin\$/,/^# $MARK end\$/d" "$EXCLUDE" >"$EXCLUDE.tmp"
  mv "$EXCLUDE.tmp" "$EXCLUDE"
  rm -f "$STATE"
  echo "detached: $TARGET (the .workbench clone itself is kept and stays excluded)"
}

case "${1:-}" in
  --detach)
    use_target "${2:-}"
    detach
    ;;
  -h | --help)
    sed -n '2,10p' "$0"
    ;;
  *)
    use_target "${1:-}"
    if [ -f "$STATE" ]; then detach; fi
    attach
    ;;
esac
