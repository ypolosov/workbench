#!/usr/bin/env bats
# A project folder moved elsewhere, e.g. mounted into a devcontainer: the links are
# relative, and setup.sh repairs git's record of the FPF worktree. Tests run in file order.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  make_sandbox
  export P="$SANDBOX/project" MOVED="$SANDBOX/moved/project"
  new_project "$P"
  install_into "$P" --repo "$PRIVATE"
  mkdir "$SANDBOX/moved"
  mv "$P" "$MOVED"
}

@test "FPF открывается по относительной ссылке" {
  [ "$(git -C "$MOVED/.workbench/.fpf" rev-parse HEAD)" = "$FPF_PINNED" ]
}

@test "скиллы доступны" {
  skills_linked "$MOVED"
}

@test "начало сессии видит новое место и закреплённое издание" {
  ctx="$(session_context "$MOVED")"
  [[ $ctx == *"\$FPF = $MOVED/.workbench/.fpf (издание ${FPF_PINNED:0:7})"* ]]
}

@test "setup.sh на новом месте чинит запись о рабочей копии FPF" {
  sh "$MOVED/.workbench/scripts/setup.sh"
  git -C "$MOVED/.workbench" worktree list --porcelain | grep -qxF "worktree $MOVED/.workbench/.fpf"
}
