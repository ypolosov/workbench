#!/bin/sh
# Connects the personal base of this machine to a project: .workbench in the project
# becomes a link to the base, and Claude Code gets the base's instructions, memory,
# hooks and skills through local files. Nothing is committed into the project: every
# path made there is listed in the project's .git/info/exclude and recorded in a state
# file inside its git dir, so that detach removes exactly that.
#
# Usage (normally through the workbench command):
#   attach.sh [<folder>]            connect to the project of the folder (default: current)
#   attach.sh --detach [<folder>]   remove exactly what attach made; the base stays
set -eu

WB_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=paths.sh
. "$WB_DIR/scripts/paths.sh"

MARK="workbench:attach"
# Expanded by the shell that runs each hook, not here.
# shellcheck disable=SC2016
HOOKS='$CLAUDE_PROJECT_DIR/.workbench/adapters/claude/hooks'

die() {
  echo "workbench: $*" >&2
  exit 1
}

# Sets TARGET (the root of the folder's project), STATE and EXCLUDE.
use_target() {
  target_dir="${1:-.}"
  [ -d "$target_dir" ] || die "нет такой папки: $target_dir"
  TARGET="$(git -C "$target_dir" rev-parse --show-toplevel 2>/dev/null)" ||
    die "это не git-проект: $target_dir. Запусти команду в папке проекта."
  TARGET="$(cd "$TARGET" && pwd -P)"
  [ "$TARGET" != "$WB_DIR" ] || die "это сама личная база: подключать её к себе не нужно"
  git_dir="$(git -C "$TARGET" rev-parse --absolute-git-dir)"
  STATE="$git_dir/workbench-attach.state"
  EXCLUDE="$git_dir/info/exclude"
}

record() {
  echo "$1 $2" >>"$STATE"
}

# .workbench becomes a link to the base. The link is absolute: a moved project keeps it,
# and a devcontainer that mounts the base at the same path sees it too.
link_base() {
  base_link="$TARGET/.workbench"
  if [ -L "$base_link" ]; then
    wb_unlink "$base_link"
  elif [ -e "$base_link" ]; then
    die "в проекте уже есть .workbench, и это не ссылка (старая копия базы?): $base_link. Убедись, что в ней нет несохранённого, убери её и повтори."
  fi
  wb_link "$WB_DIR" "$base_link"
  record link .workbench
}

claude_block() {
  cat <<EOF
<!-- $MARK begin: local lines, never commit them. Remove with: workbench detach -->
# Подключён workbench

- \$WORKBENCH = .workbench (ссылка на личную базу этой машины)
- \$FPF = .workbench/.fpf (закреплённое издание FPF)

@.workbench/AGENTS.md

Личная память владельца (файлы - в .workbench/memory/):

@.workbench/memory/MEMORY.md
<!-- $MARK end -->
EOF
}

# strip_block <file>: removes the workbench block and the empty line written before it,
# so the owner's own text stays exactly as it was.
strip_block() {
  awk -v begin="<!-- $MARK begin" -v end="<!-- $MARK end -->" '
    skip {
      if ($0 == end) skip = 0
      next
    }
    index($0, begin) == 1 {
      skip = 1
      held = 0
      next
    }
    held {
      print ""
      held = 0
    }
    $0 == "" {
      held = 1
      next
    }
    { print }
    END { if (held) print "" }
  ' "$1" >"$1.wb-tmp"
  mv "$1.wb-tmp" "$1"
}

# The project's own CLAUDE.local.md stays: the workbench lines go into a marked block
# at its end. Without one, the file is created.
write_claude_local() {
  claude_local="$TARGET/CLAUDE.local.md"
  if [ -e "$claude_local" ]; then
    {
      echo
      claude_block
    } >>"$claude_local"
    record block CLAUDE.local.md
  else
    claude_block >"$claude_local"
    record created CLAUDE.local.md
  fi
}

# Hooks of the Claude Code adapter plus the owner's optional overlay.
settings_json() {
  wb_with_overlay "$(wb_hooks_json "$HOOKS")"
}

# Creates .claude/settings.local.json, or merges into an existing one after a backup.
write_settings() {
  settings_file="$TARGET/.claude/settings.local.json"
  if [ ! -d "$TARGET/.claude" ]; then
    mkdir "$TARGET/.claude"
    record created-dir .claude
  fi
  ours="$(settings_json)"
  if [ -f "$settings_file" ]; then
    cp "$settings_file" "$settings_file.wb-backup"
    record backup .claude/settings.local.json
    # Merge into a temporary file: the project's own file changes only on success.
    if ! printf '%s' "$ours" | jq -s "$MERGE_JQ" "$settings_file.wb-backup" - >"$settings_file.wb-tmp"; then
      rm -f "$settings_file.wb-tmp"
      die "cannot merge into $settings_file (left unchanged; run workbench detach to clean up)"
    fi
    mv "$settings_file.wb-tmp" "$settings_file"
  else
    printf '%s\n' "$ours" >"$settings_file"
    record created .claude/settings.local.json
  fi
}

link_skills() {
  if [ ! -d "$TARGET/.claude/skills" ]; then
    mkdir "$TARGET/.claude/skills"
    record created-dir .claude/skills
  fi
  for skill in "$WB_DIR"/.agents/skills/*/; do
    name="$(basename "$skill")"
    skill_link="$TARGET/.claude/skills/$name"
    if [ -e "$skill_link" ] || [ -L "$skill_link" ]; then
      echo "workbench: скилл $name в проекте уже есть, пропускаю" >&2
      continue
    fi
    wb_link "../../.workbench/.agents/skills/$name" "$skill_link"
    record link ".claude/skills/$name"
  done
}

write_exclude() {
  {
    echo "# $MARK begin"
    grep -E '^(link|created|created-dir|backup) ' "$STATE" | sed 's#^[^ ]* #/#'
    if grep -q '^backup ' "$STATE"; then echo "/.claude/settings.local.json.wb-backup"; fi
    echo "# $MARK end"
  } >>"$EXCLUDE"
}

# A devcontainer sees only the project folder: the base must be mounted at the same path.
devcontainer_hint() {
  for config in "$TARGET/.devcontainer/devcontainer.json" "$TARGET/.devcontainer.json"; do
    [ -f "$config" ] || continue
    echo "workbench: в контейнере база видна, только если смонтировать её по тому же пути. Добавь в \"mounts\" файла $config:"
    printf '  {"source": "%s", "target": "%s", "type": "bind"}\n' "$WB_DIR" "$WB_DIR"
    return 0
  done
}

attach() {
  [ -d "$FPF_DIR" ] || die "база не подготовлена: запусти sh $WB_DIR/scripts/setup.sh"
  mkdir -p "$(dirname "$EXCLUDE")"
  : >"$STATE"
  link_base
  write_claude_local
  write_settings
  link_skills
  write_exclude
  echo "workbench: подключено к $TARGET (.workbench -> $WB_DIR)"
  echo "workbench: инструкции и память базы лежат вне проекта, поэтому при первом запуске в этом проекте Claude Code спросит про внешние импорты: ответь «Yes, allow external imports»."
  devcontainer_hint
}

detach() {
  [ -f "$STATE" ] || die "база не подключена к $TARGET"
  # Undo in reverse order: files and links first, then the directories that held them.
  awk '{ lines[NR] = $0 } END { for (i = NR; i > 0; i--) print lines[i] }' "$STATE" |
    while read -r kind rel; do
      case "$kind" in
        link) wb_unlink "$TARGET/$rel" ;;
        created) rm -f "${TARGET:?}/$rel" ;;
        block) strip_block "$TARGET/$rel" ;;
        backup) mv -f "$TARGET/$rel.wb-backup" "$TARGET/$rel" ;;
        created-dir) rmdir "$TARGET/$rel" 2>/dev/null || echo "workbench: оставляю непустую папку $rel" >&2 ;;
      esac
    done
  sed "/^# $MARK begin\$/,/^# $MARK end\$/d" "$EXCLUDE" >"$EXCLUDE.tmp"
  mv "$EXCLUDE.tmp" "$EXCLUDE"
  rm -f "$STATE"
  echo "workbench: отключено от $TARGET; база осталась в $WB_DIR"
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
    if [ -f "$STATE" ]; then detach >/dev/null; fi
    attach
    ;;
esac
