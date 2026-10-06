#!/bin/sh
# Import published program history without committing personal or unsaved work.
# Caller defines WB_DIR and passes a clean, checked-out template snapshot.
wb_program_path() {
  case $1 in
    bin/* | scripts/* | adapters/*/hooks/* | .githooks/* | .github/* | tests/* | .agents/skills/* | AGENTS.md | \
      install.sh | install.ps1 | README.md | Makefile | LICENSE | THIRD-PARTY.md | \
      .gitignore | .gitattributes | .editorconfig | .shellcheckrc) return 0 ;;
    *) return 1 ;;
  esac
}
wb_upgrade_error() {
  printf 'workbench: %s; исходные файлы и личные изменения сохранены\n' "$*" >&2
  return 1
}
wb_upgrade_object() {
  git -C "$WB_DIR" rev-parse --verify -q "$1:$2" 2>/dev/null || printf '%s\n' -
}
# Old installers did not always record a version. Only exact published blobs count.
wb_upgrade_was_published() {
  git -C "$WB_DIR" log --format=%H "$wb_upgrade_version" -- "$wb_upgrade_file" >"$wb_upgrade_stage/candidates" || return 1
  while IFS= read -r wb_upgrade_candidate; do
    [ "$(wb_upgrade_object "$wb_upgrade_candidate" "$wb_upgrade_file")" != "$1" ] || return 0
  done <"$wb_upgrade_stage/candidates"
  return 1
}
# Known published copies are installations; other changes remain unsaved.
wb_upgrade_unsaved() {
  wb_upgrade_local=$1 wb_upgrade_original=$2 wb_upgrade_vendor=$3
  if [ "$wb_upgrade_local" = "$wb_upgrade_original" ] ||
    [ "$wb_upgrade_local" = "$wb_upgrade_vendor" ] ||
    { [ "$wb_upgrade_overlay" != - ] && [ "$wb_upgrade_local" = "$wb_upgrade_overlay" ]; }; then
    printf '%s\n' "$wb_upgrade_vendor"
    return 0
  fi
  if [ "$wb_upgrade_local" != - ] && wb_upgrade_was_published "$wb_upgrade_local"; then
    printf '%s\n' "$wb_upgrade_vendor"
    return 0
  fi
  if [ "$wb_upgrade_local" = - ] || [ "$wb_upgrade_vendor" = - ] || [ "$wb_upgrade_original" = - ]; then
    wb_upgrade_error "местная правка или удаление $wb_upgrade_file несовместимы с обновлением"
    return 1
  fi
  wb_upgrade_ancestor=$wb_upgrade_original
  [ "$wb_upgrade_overlay" = - ] || wb_upgrade_ancestor=$wb_upgrade_overlay
  git -C "$WB_DIR" cat-file blob "$wb_upgrade_local" >"$wb_upgrade_stage/local"
  git -C "$WB_DIR" cat-file blob "$wb_upgrade_ancestor" >"$wb_upgrade_stage/ancestor"
  git -C "$WB_DIR" cat-file blob "$wb_upgrade_vendor" >"$wb_upgrade_stage/vendor"
  if ! git merge-file --quiet "$wb_upgrade_stage/local" "$wb_upgrade_stage/ancestor" "$wb_upgrade_stage/vendor"; then
    wb_upgrade_error "конфликт местных правок в $wb_upgrade_file"
    return 1
  fi
  git -C "$WB_DIR" hash-object -w "$wb_upgrade_stage/local"
}
wb_upgrade_cleanup() {
  if [ "$wb_upgrade_written" = 1 ] && [ "$wb_upgrade_done" != 1 ]; then
    if [ "$wb_upgrade_ref_changed" = 1 ]; then
      git -C "$WB_DIR" update-ref HEAD "$wb_upgrade_before" "$wb_upgrade_after" || true
    fi
    while IFS= read -r wb_upgrade_file; do
      if [ -f "$wb_upgrade_backup/$wb_upgrade_file" ]; then
        cp -p "$wb_upgrade_backup/$wb_upgrade_file" "$WB_DIR/$wb_upgrade_file"
      else rm -f -- "$WB_DIR/$wb_upgrade_file"; fi
    done <"$wb_upgrade_stage/changed"
  fi
  [ "$wb_upgrade_index_locked" != 1 ] || rm -f -- "$wb_upgrade_index.lock"
  if [ -n "$wb_upgrade_stage" ] && [ -d "$wb_upgrade_stage/tree" ]; then
    # Only this invocation's temporary worktree is removed.
    git -C "$WB_DIR" worktree remove --force "$wb_upgrade_stage/tree" >/dev/null 2>&1 || true
  fi
  rmdir "$WB_DIR/.runtime/upgrade.lock" 2>/dev/null || true
}
wb_upgrade_program() (
  set -eu
  wb_upgrade_source=$1
  wb_upgrade_stage=""
  wb_upgrade_written=0 wb_upgrade_done=0 wb_upgrade_ref_changed=0 wb_upgrade_index_locked=0
  mkdir -p "$WB_DIR/.runtime"
  if ! mkdir "$WB_DIR/.runtime/upgrade.lock" 2>/dev/null; then
    wb_upgrade_error 'другое обновление уже выполняется'
    exit 1
  fi
  trap 'wb_upgrade_cleanup' 0
  trap 'exit 130' INT
  trap 'exit 143' TERM
  wb_upgrade_index="$(git -C "$WB_DIR" rev-parse --path-format=absolute --git-path index)"
  if command -v cygpath >/dev/null 2>&1; then wb_upgrade_index="$(cygpath -u "$wb_upgrade_index")"; fi
  if ! (
    set -C
    : >"$wb_upgrade_index.lock"
  ) 2>/dev/null; then
    wb_upgrade_error 'Git занят другой операцией'
    exit 1
  fi
  wb_upgrade_index_locked=1
  [ -z "$(git -C "$WB_DIR" ls-files --unmerged)" ] || {
    wb_upgrade_error 'в базе есть незавершённое слияние'
    exit 1
  }
  for wb_upgrade_state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    [ ! -e "$(git -C "$WB_DIR" rev-parse --path-format=absolute --git-path "$wb_upgrade_state")" ] || {
      wb_upgrade_error 'сначала завершите текущую операцию Git'
      exit 1
    }
  done
  [ -z "$(git -C "$wb_upgrade_source" status --porcelain)" ] || {
    wb_upgrade_error 'обновление допускает только опубликованный снимок шаблона'
    exit 1
  }
  wb_upgrade_before="$(git -C "$WB_DIR" rev-parse HEAD)"
  wb_upgrade_version="$(git -C "$wb_upgrade_source" rev-parse HEAD)"
  # Git merge itself requires an identity, even with --no-commit.
  if ! git -C "$WB_DIR" var GIT_AUTHOR_IDENT >/dev/null 2>&1; then
    GIT_AUTHOR_NAME=workbench GIT_AUTHOR_EMAIL=updates@workbench.invalid
    export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL
  fi
  if ! git -C "$WB_DIR" var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
    GIT_COMMITTER_NAME=workbench GIT_COMMITTER_EMAIL=updates@workbench.invalid
    export GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  fi
  git -C "$WB_DIR" fetch -q --no-tags "$wb_upgrade_source" "$wb_upgrade_version"
  git -C "$WB_DIR" merge-base "$wb_upgrade_before" "$wb_upgrade_version" >/dev/null || {
    wb_upgrade_error 'история базы не связана с выбранным шаблоном'
    exit 1
  }
  wb_upgrade_previous=-
  if [ -f "$WB_DIR/.runtime/program-version" ]; then
    wb_upgrade_previous="$(cat "$WB_DIR/.runtime/program-version")"
    if ! git -C "$WB_DIR" merge-base --is-ancestor "$wb_upgrade_previous" "$wb_upgrade_version" 2>/dev/null ||
      git -C "$WB_DIR" merge-base --is-ancestor "$wb_upgrade_previous" "$wb_upgrade_before" 2>/dev/null; then
      wb_upgrade_previous=-
    fi
  fi
  wb_upgrade_stage="$(mktemp -d "${TMPDIR:-/tmp}/workbench-upgrade.XXXXXX")"
  wb_upgrade_stage="$(cd "$wb_upgrade_stage" && pwd -P)"
  wb_upgrade_backup="$WB_DIR/.runtime/backups/$(basename "$wb_upgrade_stage")"
  git -C "$WB_DIR" worktree add -q --detach "$wb_upgrade_stage/tree" "$wb_upgrade_before"
  # Personal seed files always stay ours, including conflicts and template additions.
  if ! git -C "$wb_upgrade_stage/tree" merge -q --no-commit --no-ff "$wb_upgrade_version" >"$wb_upgrade_stage/merge.log" 2>&1; then
    [ -f "$(git -C "$wb_upgrade_stage/tree" rev-parse --path-format=absolute --git-path MERGE_HEAD)" ] || {
      wb_upgrade_error 'не удалось подготовить историю обновления'
      exit 1
    }
  fi
  {
    git -C "$wb_upgrade_stage/tree" -c core.quotePath=false diff --name-only "$wb_upgrade_before"
    git -C "$wb_upgrade_stage/tree" -c core.quotePath=false diff --name-only --diff-filter=U
  } |
    LC_ALL=C sort -u >"$wb_upgrade_stage/merged"
  while IFS= read -r wb_upgrade_file; do
    wb_program_path "$wb_upgrade_file" && continue
    if git -C "$WB_DIR" cat-file -e "$wb_upgrade_before:$wb_upgrade_file" 2>/dev/null; then
      git -C "$wb_upgrade_stage/tree" restore --source "$wb_upgrade_before" --staged --worktree -- "$wb_upgrade_file"
    else git -C "$wb_upgrade_stage/tree" rm -q -f --ignore-unmatch -- "$wb_upgrade_file"; fi
  done <"$wb_upgrade_stage/merged"
  if [ -n "$(git -C "$wb_upgrade_stage/tree" ls-files --unmerged)" ]; then
    wb_upgrade_error 'конфликт сохранённых местных правок программы'
    exit 1
  fi
  if [ -f "$(git -C "$wb_upgrade_stage/tree" rev-parse --path-format=absolute --git-path MERGE_HEAD)" ]; then
    git -C "$wb_upgrade_stage/tree" -c core.quotePath=false diff --cached --name-only >"$wb_upgrade_stage/staged"
    while IFS= read -r wb_upgrade_file; do
      wb_program_path "$wb_upgrade_file" || {
        wb_upgrade_error "личный файл $wb_upgrade_file попал в обновление"
        exit 1
      }
    done <"$wb_upgrade_stage/staged"
    wb_upgrade_message="workbench: update program to $wb_upgrade_version"
    if git -C "$wb_upgrade_stage/tree" var GIT_AUTHOR_IDENT >/dev/null 2>&1; then
      git -C "$wb_upgrade_stage/tree" commit -qm "$wb_upgrade_message"
    else git -C "$wb_upgrade_stage/tree" -c user.name=workbench -c user.email=updates@workbench.invalid commit -qm "$wb_upgrade_message"; fi
  fi
  wb_upgrade_after="$(git -C "$wb_upgrade_stage/tree" rev-parse HEAD)"
  cp "$wb_upgrade_index" "$wb_upgrade_stage/index"
  cp "$wb_upgrade_index" "$wb_upgrade_stage/working-index"
  git -C "$WB_DIR" -c core.quotePath=false diff --name-only "$wb_upgrade_before" "$wb_upgrade_after" >"$wb_upgrade_stage/changed"
  : >"$wb_upgrade_stage/checkout"
  : >"$wb_upgrade_stage/remove"
  while IFS= read -r wb_upgrade_file; do
    wb_upgrade_parent=$wb_upgrade_file
    while [ "$wb_upgrade_parent" != . ]; do
      [ ! -L "$WB_DIR/$wb_upgrade_parent" ] || {
        wb_upgrade_error "локальная ссылка $wb_upgrade_parent требует сохранения"
        exit 1
      }
      wb_upgrade_parent="$(dirname "$wb_upgrade_parent")"
    done
    [ ! -d "$WB_DIR/$wb_upgrade_file" ] || {
      wb_upgrade_error "на месте файла $wb_upgrade_file находится каталог"
      exit 1
    }
    wb_upgrade_old="$(wb_upgrade_object "$wb_upgrade_before" "$wb_upgrade_file")"
    wb_upgrade_new="$(wb_upgrade_object "$wb_upgrade_after" "$wb_upgrade_file")"
    wb_upgrade_overlay=-
    [ "$wb_upgrade_previous" = - ] || wb_upgrade_overlay="$(wb_upgrade_object "$wb_upgrade_previous" "$wb_upgrade_file")"
    wb_upgrade_cached="$(wb_upgrade_object "" "$wb_upgrade_file")"
    wb_upgrade_working=-
    if [ -f "$WB_DIR/$wb_upgrade_file" ]; then
      wb_upgrade_working="$(git -C "$WB_DIR" hash-object -w --path "$wb_upgrade_file" "$WB_DIR/$wb_upgrade_file")"
      mkdir -p "$wb_upgrade_backup/$(dirname "$wb_upgrade_file")"
      cp -p "$WB_DIR/$wb_upgrade_file" "$wb_upgrade_backup/$wb_upgrade_file"
    fi
    wb_upgrade_cached="$(wb_upgrade_unsaved "$wb_upgrade_cached" "$wb_upgrade_old" "$wb_upgrade_new")" || exit 1
    wb_upgrade_working="$(wb_upgrade_unsaved "$wb_upgrade_working" "$wb_upgrade_old" "$wb_upgrade_new")" || exit 1
    if [ "$wb_upgrade_new" = - ]; then
      GIT_INDEX_FILE="$wb_upgrade_stage/index" git -C "$WB_DIR" update-index --force-remove -- "$wb_upgrade_file"
      GIT_INDEX_FILE="$wb_upgrade_stage/working-index" git -C "$WB_DIR" update-index --force-remove -- "$wb_upgrade_file"
      printf '%s\n' "$wb_upgrade_file" >>"$wb_upgrade_stage/remove"
    else
      wb_upgrade_mode="$(git -C "$WB_DIR" ls-tree --format='%(objectmode)' "$wb_upgrade_after" -- "$wb_upgrade_file")"
      GIT_INDEX_FILE="$wb_upgrade_stage/index" git -C "$WB_DIR" update-index --add --cacheinfo "$wb_upgrade_mode,$wb_upgrade_cached,$wb_upgrade_file"
      GIT_INDEX_FILE="$wb_upgrade_stage/working-index" git -C "$WB_DIR" update-index --add --cacheinfo "$wb_upgrade_mode,$wb_upgrade_working,$wb_upgrade_file"
      printf '%s\n' "$wb_upgrade_file" >>"$wb_upgrade_stage/checkout"
    fi
  done <"$wb_upgrade_stage/changed"
  # The real index is locked; nothing is published until all files passed preflight.
  cp "$wb_upgrade_stage/index" "$wb_upgrade_index.lock"
  wb_upgrade_written=1
  GIT_INDEX_FILE="$wb_upgrade_stage/working-index" git -C "$WB_DIR" checkout-index --force --stdin <"$wb_upgrade_stage/checkout"
  while IFS= read -r wb_upgrade_file; do rm -f -- "$WB_DIR/$wb_upgrade_file"; done <"$wb_upgrade_stage/remove"
  git -C "$WB_DIR" update-ref -m "workbench program update" HEAD "$wb_upgrade_after" "$wb_upgrade_before"
  wb_upgrade_ref_changed=1
  mv "$wb_upgrade_index.lock" "$wb_upgrade_index"
  wb_upgrade_index_locked=0
  wb_upgrade_done=1
  printf '%s\n' "$wb_upgrade_version" >"$WB_DIR/.runtime/program-version"
  wb_upgrade_exclude="$(git -C "$WB_DIR" rev-parse --git-path info/exclude)"
  case "$wb_upgrade_exclude" in /*) ;; *) wb_upgrade_exclude="$WB_DIR/$wb_upgrade_exclude" ;; esac
  mkdir -p "$(dirname "$wb_upgrade_exclude")"
  touch "$wb_upgrade_exclude"
  grep -qxF '/.runtime/' "$wb_upgrade_exclude" || printf '/.runtime/\n' >>"$wb_upgrade_exclude"
)
