#!/usr/bin/env bats
# The private base shared by several projects: checks before saving, a second project
# that clones the existing base, exchange of records and the history guard.
# Tests run in file order.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  make_sandbox
  export P1="$SANDBOX/project-one" WB1="$SANDBOX/project-one/.workbench"
  export P2="$SANDBOX/project-two" WB2="$SANDBOX/project-two/.workbench"
  new_project "$P1"
  new_project "$P2"
  install_into "$P1" --repo "$PRIVATE"
  printf 'acme-internal\n' >>"$(git -C "$WB1" rev-parse --absolute-git-dir)/info/company-markers"
}

@test "запись с маркером компании не сохраняется" {
  run ! commit_note "$WB1" "Встреча по ACME-Internal"
  [ "$(git -C "$WB1" rev-parse HEAD)" = "$(git -C "$PRIVATE" rev-parse main)" ]
  git -C "$WB1" diff --quiet HEAD
}

@test "запись с текстом, похожим на ключ доступа, не сохраняется" {
  # Split so that this file holds no key-like string.
  run ! commit_note "$WB1" "key AKIA""TESTKEY000000000"
  [ "$(git -C "$WB1" rev-parse HEAD)" = "$(git -C "$PRIVATE" rev-parse main)" ]
}

@test "второй проект получает существующую базу, даже когда HEAD хранилища указывает на отсутствующую ветку" {
  # `git init --bare` leaves HEAD at master where master is the default branch.
  git -C "$PRIVATE" symbolic-ref HEAD refs/heads/master
  install_into "$P2" --repo "$PRIVATE"
  [ "$(git -C "$WB2" rev-parse --abbrev-ref HEAD)" = main ]
  [ "$(git -C "$WB2" rev-parse HEAD)" = "$(git -C "$PRIVATE" rev-parse main)" ]
  remotes_ok "$WB2"
  [ "$(git -C "$WB2/.fpf" rev-parse HEAD)" = "$FPF_PINNED" ]
  [ -z "$(git -C "$P2" status --porcelain)" ]
}

@test "запись из второго проекта доходит до первого через личную базу" {
  commit_note "$WB2" "заметка из второго проекта"
  git -C "$WB2" push -q origin HEAD
  install_into "$P1"
  [ "$(git -C "$WB1" rev-parse HEAD)" = "$(git -C "$PRIVATE" rev-parse main)" ]
  grep -qxF "заметка из второго проекта" "$WB1/inbox/fleeting-notes.md"
}

@test "перезапись истории личной базы отклонена" {
  local pushed
  pushed="$(git -C "$PRIVATE" rev-parse main)"
  git -C "$WB1" commit -q --amend -m "test: rewritten history"
  run ! git -C "$WB1" push -q --force origin HEAD:main
  [ "$(git -C "$PRIVATE" rev-parse main)" = "$pushed" ]
}
