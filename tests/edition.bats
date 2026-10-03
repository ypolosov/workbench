#!/usr/bin/env bats
# A newer FPF edition reaches a base that already exists: the template pins another
# commit, the base merges that update, the session start names the command, and setup.sh
# moves the .fpf worktree to the newly pinned edition. Tests run in file order.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  make_sandbox
  export BASE="$SANDBOX/my-workbench"
  bootstrap "$BASE" --repo "$PRIVATE"
  sed "s/^commit=.*/commit=$FPF_NEWER/" "$TPL/.fpf-edition" >"$SANDBOX/edition"
  cp "$SANDBOX/edition" "$TPL/.fpf-edition"
  git -C "$TPL" commit -qam "pin a newer FPF edition"
  git -C "$BASE" pull -q template main
}

@test "после смены издания начало сессии предупреждает и называет команду обновления" {
  ctx="$(session_context "$BASE")"
  [[ $ctx == *"ВНИМАНИЕ: закреплено издание ${FPF_NEWER:0:7}"* ]]
  [[ $ctx == *"$BASE/scripts/setup.sh"* ]]
}

@test "setup.sh переводит рабочую копию FPF на новое закреплённое издание" {
  sh "$BASE/scripts/setup.sh"
  [ "$(git -C "$BASE/.fpf" rev-parse HEAD)" = "$FPF_NEWER" ]
  git -C "$BASE" worktree list --porcelain | grep -q '^locked'
}

@test "после обновления начало сессии называет новое издание без предупреждения" {
  ctx="$(session_context "$BASE")"
  [[ $ctx == *"(издание ${FPF_NEWER:0:7})"* ]]
  [[ $ctx != *"закреплено издание"* ]]
}
