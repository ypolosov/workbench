#!/bin/sh
# Update program files only. Personal materials and settings stay in the base.
# Caller defines WB_DIR (base) and passes a checked-out template snapshot.
wb_upgrade_program() {
  wb_upgrade_source=$1
  wb_upgrade_stage="$(mktemp -d "${TMPDIR:-/tmp}/workbench-upgrade.XXXXXX")"
  git -C "$wb_upgrade_source" ls-files bin scripts adapters .githooks install.sh install.ps1 >"$wb_upgrade_stage/files"
  : >"$wb_upgrade_stage/changed"
  while IFS= read -r wb_upgrade_file; do
    [ -f "$wb_upgrade_source/$wb_upgrade_file" ] || continue
    wb_upgrade_target="$WB_DIR/$wb_upgrade_file"
    cmp -s "$wb_upgrade_source/$wb_upgrade_file" "$wb_upgrade_target" && continue
    [ ! -L "$wb_upgrade_target" ] || {
      printf 'workbench: сохраняю локальную ссылку %s; обновление остановлено\n' "$wb_upgrade_file" >&2
      return 1
    }
    mkdir -p "$wb_upgrade_stage/new/$(dirname "$wb_upgrade_file")" "$wb_upgrade_stage/old/$(dirname "$wb_upgrade_file")"
    cp "$wb_upgrade_source/$wb_upgrade_file" "$wb_upgrade_stage/new/$wb_upgrade_file"
    if [ -e "$wb_upgrade_target" ]; then
      cp "$wb_upgrade_target" "$wb_upgrade_stage/old/$wb_upgrade_file"
      if ! git -C "$WB_DIR" show "HEAD:$wb_upgrade_file" >"$wb_upgrade_stage/ancestor"; then
        printf 'workbench: локальный файл %s отличается от программы; сохранён без изменений\n' "$wb_upgrade_file" >&2
        return 1
      fi
      if ! cmp -s "$wb_upgrade_target" "$wb_upgrade_stage/ancestor"; then
        cp "$wb_upgrade_target" "$wb_upgrade_stage/new/$wb_upgrade_file"
        if ! git merge-file --quiet "$wb_upgrade_stage/new/$wb_upgrade_file" \
          "$wb_upgrade_stage/ancestor" "$wb_upgrade_source/$wb_upgrade_file"; then
          printf 'workbench: конфликт местных правок в %s; исходные файлы сохранены\n' "$wb_upgrade_file" >&2
          return 1
        fi
      fi
    elif git -C "$WB_DIR" cat-file -e "HEAD:$wb_upgrade_file" 2>/dev/null; then
      printf 'workbench: %s удалён локально; исходные файлы сохранены\n' "$wb_upgrade_file" >&2
      return 1
    fi
    printf '%s\n' "$wb_upgrade_file" >>"$wb_upgrade_stage/changed"
  done <"$wb_upgrade_stage/files"
  wb_upgrade_backup="$WB_DIR/.runtime/backups/$(basename "$wb_upgrade_stage")"
  while IFS= read -r wb_upgrade_file; do
    if [ -f "$wb_upgrade_stage/old/$wb_upgrade_file" ]; then
      mkdir -p "$wb_upgrade_backup/$(dirname "$wb_upgrade_file")"
      cp "$wb_upgrade_stage/old/$wb_upgrade_file" "$wb_upgrade_backup/$wb_upgrade_file"
    fi
    mkdir -p "$WB_DIR/$(dirname "$wb_upgrade_file")"
    cp "$wb_upgrade_stage/new/$wb_upgrade_file" "$WB_DIR/$wb_upgrade_file"
    [ ! -x "$wb_upgrade_source/$wb_upgrade_file" ] || chmod +x "$WB_DIR/$wb_upgrade_file"
  done <"$wb_upgrade_stage/changed"
  mkdir -p "$WB_DIR/.runtime"
  git -C "$wb_upgrade_source" rev-parse HEAD >"$WB_DIR/.runtime/program-version"
  wb_upgrade_exclude="$(git -C "$WB_DIR" rev-parse --git-path info/exclude)"
  case "$wb_upgrade_exclude" in /*) ;; *) wb_upgrade_exclude="$WB_DIR/$wb_upgrade_exclude" ;; esac
  mkdir -p "$(dirname "$wb_upgrade_exclude")"
  touch "$wb_upgrade_exclude"
  grep -qxF '/.runtime/' "$wb_upgrade_exclude" || printf '/.runtime/\n' >>"$wb_upgrade_exclude"
}
