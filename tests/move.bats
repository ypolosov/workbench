#!/usr/bin/env bats
# Moving folders: a moved project keeps working, because the link to the base is
# absolute; a moved base is fixed by installing again with the new path and attaching
# again. Tests run in file order.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  make_sandbox
  export BASE="$SANDBOX/my-workbench" P="$SANDBOX/project" MOVED="$SANDBOX/moved/project"
  bootstrap "$BASE" --repo "$PRIVATE"
  new_project "$P"
  wb "$P" attach
  mkdir "$SANDBOX/moved"
  mv "$P" "$MOVED"
}

@test "проект перенесён: ссылка на базу абсолютная и продолжает работать" {
  [ "$(cd "$MOVED/.workbench" && pwd -P)" = "$BASE" ]
  skills_linked "$MOVED"
  ctx="$(session_context "$MOVED")"
  [[ $ctx == *"\$WORKBENCH = $BASE"* ]]
}

@test "база перенесена: установка с новым путём и повторное подключение всё чинят" {
  local newbase="$SANDBOX/elsewhere/my-workbench"
  mkdir "$SANDBOX/elsewhere"
  mv "$BASE" "$newbase"
  bootstrap "$newbase"
  worktree_listed "$newbase" "$newbase/.fpf"
  [ "$(git -C "$newbase/.fpf" rev-parse HEAD)" = "$FPF_PINNED" ]
  wb "$MOVED" attach
  [ "$(cd "$MOVED/.workbench" && pwd -P)" = "$newbase" ]
  [ -z "$(git -C "$MOVED" status --porcelain)" ]
}
