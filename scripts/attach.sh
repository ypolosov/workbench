#!/bin/sh
# Connects the personal base of this machine to AI agents: Claude Code, Codex and Cursor.
# On the user level, a marked block in the user's CLAUDE.md imports the base's
# instructions and memory into every Claude Code project, and a marked block in Codex's
# user-level AGENTS.md points Codex to them (Codex has no imports). In a project,
# .workbench becomes a link to the base, and the agents get the base's hooks, skills and a
# pointer to its instructions through local files: Claude Code's settings.local.json
# (Cursor runs these hooks too), Codex's hooks.json, Cursor's rule, and links to the
# skills in .claude/skills (Claude Code) and .agents/skills (Codex, Cursor). Nothing is
# committed into the project: every path made there is listed in the project's
# .git/info/exclude and recorded in a state file inside its git dir, so that detach
# removes exactly that. A file the project's git tracks belongs to its team and stays.
#
# Usage (normally through the workbench command):
#   attach.sh [<folder>]            connect to the project of the folder (default: current)
#   attach.sh --detach [<folder>]   remove exactly what attach made; the base stays
#   attach.sh --user                point the agents to the base's instructions and memory
#   attach.sh --detach --user       remove that; the user's own lines stay
set -eu

WB_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=paths.sh
. "$WB_DIR/scripts/paths.sh"

MARK="workbench:attach"
USER_MARK="workbench:user"
# The hooks speak Claude Code's protocol; Codex speaks it too, Cursor translates it.
ADAPTER=.workbench/adapters/claude/hooks
# Expanded by the shell that runs each hook, not here.
# shellcheck disable=SC2016
CLAUDE_HOOK='"$CLAUDE_PROJECT_DIR/'"$ADAPTER"'/%s"'

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

codex_block() {
  echo "<!-- $USER_MARK begin: lines of the workbench command. Remove with: workbench detach --user -->"
  wb_read_note
  echo "<!-- $USER_MARK end -->"
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

# put_block <file> <block>: puts the block of this command at the end of the user's file
# instead of the one there; the owner's own text and a link to the file stay.
put_block() {
  mkdir -p "$(dirname "$1")"
  if [ -f "$1" ]; then strip_block "$1" "$USER_MARK"; fi
  if [ -s "$1" ]; then echo >>"$1"; fi
  printf '%s\n' "$2" >>"$1"
}

# drop_block <file>: removes the block of this command; a file left empty goes too.
drop_block() {
  grep -q "^<!-- $USER_MARK begin" "$1" 2>/dev/null || return 1
  strip_block "$1" "$USER_MARK"
  [ -L "$1" ] || [ -s "$1" ] || rm -f "$1"
}

attach_user() {
  require_base_ready
  put_block "$(wb_user_claude_md)" "$(user_block)"
  echo "workbench: инструкции и память базы подключены ко всем проектам Claude Code на этой машине: $(wb_user_claude_md)"
  put_block "$(wb_codex_agents_md)" "$(codex_block)"
  echo "workbench: Codex на этой машине знает, где инструкции и память базы: $(wb_codex_agents_md)"
}

detach_user() {
  removed=0
  for user_file in "$(wb_user_claude_md)" "$(wb_codex_agents_md)"; do
    if drop_block "$user_file"; then
      echo "workbench: инструкции и память базы отключены на уровне пользователя: $user_file"
      removed=1
    fi
  done
  [ "$removed" = 1 ] ||
    die "инструкции и память базы не подключены на уровне пользователя: нет блока workbench ни в $(wb_user_claude_md), ни в $(wb_codex_agents_md)"
}

# ensure_dir <folder>: makes the project's folder and every missing parent, recording them.
ensure_dir() {
  made=""
  old_ifs=$IFS
  IFS=/
  set -f
  for part in $1; do
    made="${made:+$made/}$part"
    if [ ! -d "$TARGET/$made" ]; then
      mkdir "$TARGET/$made"
      record created-dir "$made"
    fi
  done
  set +f
  IFS=$old_ifs
}

# tracked <file>: the project's git tracks the file, so it belongs to the project's team.
tracked() {
  git -C "$TARGET" ls-files --error-unmatch -- "$1" >/dev/null 2>&1
}

# merge_json <file> <json>: creates the project's local file, or merges into an existing
# one after a backup; the project's own file changes only when the merge succeeds.
merge_json() {
  if tracked "$1"; then
    echo "workbench: $1 хранится в git проекта, и его я не трогаю: этот агент остаётся без хуков workbench" >&2
    return 0
  fi
  ensure_dir "$(dirname "$1")"
  json_file="$TARGET/$1"
  if [ -f "$json_file" ]; then
    cp "$json_file" "$json_file.wb-backup"
    record backup "$1"
    if ! printf '%s' "$2" | jq -s "$MERGE_JQ" "$json_file.wb-backup" - >"$json_file.wb-tmp"; then
      rm -f "$json_file.wb-tmp"
      die "cannot merge into $json_file (left unchanged; run workbench detach to clean up)"
    fi
    mv "$json_file.wb-tmp" "$json_file"
  else
    printf '%s\n' "$2" >"$json_file"
    record created "$1"
  fi
}

# Claude Code: its hooks plus the owner's optional overlay. Cursor runs these hooks too.
claude_settings() {
  wb_with_overlay "$(wb_hooks_json "$CLAUDE_HOOK")"
}

# On Windows, Codex runs the hooks through cmd.exe: they get a commandWindows of their own.
codex_hooks() {
  windows_command=""
  if wb_windows; then
    windows_command="$(wb_codex_windows_hook_command "$(wb_git_sh)" "$(wb_native_path "$TARGET")" "$ADAPTER")"
  fi
  wb_hooks_json "$(wb_codex_hook_command "$ADAPTER")" '^Bash$' "$windows_command"
}

# Cursor: a rule in force in every session that points the agent to the base.
write_cursor_rule() {
  rule=.cursor/rules/workbench.mdc
  if [ -e "$TARGET/$rule" ]; then
    echo "workbench: $rule в проекте уже есть, его я не трогаю" >&2
    return 0
  fi
  ensure_dir .cursor/rules
  {
    printf -- '---\ndescription: workbench - личная база владельца этой машины\nalwaysApply: true\n---\n\n'
    echo "<!-- workbench: local file made by workbench attach, never commit it. Remove with: workbench detach -->"
    wb_read_note
  } >"$TARGET/$rule"
  record created "$rule"
}

# link_skills <folder>: links each skill of the base into the folder of the project; its
# own skills stay, a skill of the same name included.
link_skills() {
  ensure_dir "$1"
  for skill in "$WB_DIR"/.agents/skills/*/; do
    name="$(basename "$skill")"
    skill_link="$TARGET/$1/$name"
    if [ -e "$skill_link" ] || [ -L "$skill_link" ]; then
      echo "workbench: скилл $name в $1 проекта уже есть, пропускаю" >&2
      continue
    fi
    wb_link "../../.workbench/.agents/skills/$name" "$skill_link"
    record link "$1/$name"
  done
}

write_exclude() {
  {
    echo "# $MARK begin"
    grep -E '^(link|created|created-dir|backup) ' "$STATE" | sed 's#^[^ ]* #/#'
    grep '^backup ' "$STATE" | sed 's#^backup \(.*\)$#/\1.wb-backup#'
    echo "# $MARK end"
  } >>"$EXCLUDE"
}

# base_mounted <devcontainer.json>: the container already mounts the base at its own path,
# as an object ("target": "<base>") or as a string (target=<base>). The file is JSON with
# comments, so it is read as text rather than with jq.
base_mounted() {
  re="$(printf '%s' "$WB_DIR" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
  grep -Eq "\"target\"[[:space:]]*:[[:space:]]*\"$re\"|target=$re(,|\")" "$1"
}

# A devcontainer sees only the project folder: the base must be mounted at the same path.
devcontainer_hint() {
  for config in "$TARGET/.devcontainer/devcontainer.json" "$TARGET/.devcontainer.json"; do
    [ -f "$config" ] || continue
    base_mounted "$config" && return 0
    echo "workbench: в контейнере база видна, только если смонтировать её по тому же пути. Добавь в \"mounts\" файла $config:"
    printf '  {"source": "%s", "target": "%s", "type": "bind"}\n' "$WB_DIR" "$WB_DIR"
    printf 'workbench: у агентов в контейнере бывает своя папка настроек; тогда подключи там инструкции и память базы командой  sh "%s/bin/workbench" attach --user\n' "$WB_DIR"
    return 0
  done
}

# Names only the agents whose user-level block is missing.
user_hint() {
  missing=""
  wb_user_attached || missing="Claude Code ($(wb_user_claude_md))"
  wb_codex_attached || missing="${missing:+$missing, }Codex ($(wb_codex_agents_md))"
  [ -z "$missing" ] ||
    echo "workbench: инструкции и память базы на уровне пользователя не подключены для $missing. Подключи их один раз на этой машине: workbench attach --user"
}

attach() {
  require_base_ready
  mkdir -p "$(dirname "$EXCLUDE")"
  : >"$STATE"
  link_base
  merge_json .claude/settings.local.json "$(claude_settings)"
  merge_json .codex/hooks.json "$(codex_hooks)"
  write_cursor_rule
  link_skills .claude/skills
  link_skills .agents/skills
  write_exclude
  echo "workbench: подключено к $TARGET (.workbench -> $WB_DIR) для Claude Code, Codex и Cursor"
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
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    ;;
  *)
    use_target "${1:-}"
    if [ -f "$STATE" ]; then detach >/dev/null; fi
    attach
    ;;
esac
