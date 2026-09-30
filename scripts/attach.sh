#!/bin/sh
# Connects the personal base of this machine to Claude Code. On the user level, a marked
# block in the user's CLAUDE.md imports the base's instructions and memory into every
# project. In a project, .workbench becomes a link to the base, and Claude Code gets the
# base's hooks and skills through local files. Nothing is committed into the project:
# every path made there is listed in the project's .git/info/exclude and recorded in a
# state file inside its git dir, so that detach removes exactly that.
#
# Usage (normally through the workbench command):
#   attach.sh [<folder>]            connect to the project of the folder (default: current)
#   attach.sh --detach [<folder>]   remove exactly what attach made; the base stays
#   attach.sh --user                import the base's instructions and memory on the user level
#   attach.sh --detach --user       remove that import; the user's own lines stay
set -eu

WB_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=paths.sh
. "$WB_DIR/scripts/paths.sh"

MARK="workbench:attach"
USER_MARK="workbench:user"
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

user_block() {
  cat <<EOF
<!-- $USER_MARK begin: lines of the workbench command. Remove with: workbench detach --user -->
# Подключён workbench

- \$WORKBENCH = $(wb_native_path "$WB_DIR") (личная база этой машины)
- \$FPF = $(wb_native_path "$FPF_DIR") (закреплённое издание FPF)

$(wb_import "$WB_DIR/AGENTS.md")

Личная память владельца (файлы - в $(wb_native_path "$WB_DIR/memory")/):

$(wb_import "$WB_DIR/memory/MEMORY.md")
<!-- $USER_MARK end -->
EOF
}

# strip_block <file> <mark>: removes the block of that mark and the empty line written
# before it, so the owner's own text stays exactly as it was.
strip_block() {
  awk -v begin="<!-- $2 begin" -v end="<!-- $2 end -->" '
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
  cat "$1.wb-tmp" >"$1"
  rm -f "$1.wb-tmp"
}

require_base_ready() {
  [ -d "$FPF_DIR" ] || die "база не подготовлена: запусти sh $WB_DIR/scripts/setup.sh"
}

attach_user() {
  require_base_ready
  user_md="$(wb_user_claude_md)"
  mkdir -p "$(dirname "$user_md")"
  if [ -f "$user_md" ]; then strip_block "$user_md" "$USER_MARK"; fi
  if [ -s "$user_md" ]; then echo >>"$user_md"; fi
  user_block >>"$user_md"
  echo "workbench: инструкции и память базы подключены ко всем проектам Claude Code на этой машине: $user_md"
}

detach_user() {
  user_md="$(wb_user_claude_md)"
  grep -q "^<!-- $USER_MARK begin" "$user_md" 2>/dev/null ||
    die "инструкции и память базы не подключены на уровне пользователя: в $user_md нет блока workbench"
  strip_block "$user_md" "$USER_MARK"
  [ -L "$user_md" ] || [ -s "$user_md" ] || rm -f "$user_md"
  echo "workbench: инструкции и память базы отключены на уровне пользователя: $user_md"
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
    printf 'workbench: у Claude Code в контейнере бывает своя папка настроек; тогда подключи там инструкции и память базы командой  sh "%s/bin/workbench" attach --user\n' "$WB_DIR"
    return 0
  done
}

user_hint() {
  wb_user_attached ||
    echo "workbench: инструкции и память базы Claude Code берёт из $(wb_user_claude_md), а там их пока нет. Подключи их один раз на этой машине: workbench attach --user"
}

attach() {
  require_base_ready
  mkdir -p "$(dirname "$EXCLUDE")"
  : >"$STATE"
  link_base
  write_settings
  link_skills
  write_exclude
  echo "workbench: подключено к $TARGET (.workbench -> $WB_DIR)"
  user_hint
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
        block) strip_block "$TARGET/$rel" "$MARK" ;;
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
  --user)
    attach_user
    ;;
  --detach)
    if [ "${2:-}" = --user ]; then
      detach_user
    else
      use_target "${2:-}"
      detach
    fi
    ;;
  -h | --help)
    sed -n '2,13p' "$0"
    ;;
  *)
    use_target "${1:-}"
    if [ -f "$STATE" ]; then detach >/dev/null; fi
    attach
    ;;
esac
