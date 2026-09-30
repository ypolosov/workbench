#!/usr/bin/env bats
# Checks of the personal base before saving and before sending: company markers,
# key-like text and rewriting of the shared history.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  make_sandbox
  export BASE="$SANDBOX/my-workbench"
  bootstrap "$BASE" --repo "$PRIVATE"
  printf 'acme-internal\n' >>"$(git -C "$BASE" rev-parse --absolute-git-dir)/info/company-markers"
}

@test "запись с маркером компании не сохраняется" {
  run ! commit_note "$BASE" "Встреча по ACME-Internal"
  [ "$(git -C "$BASE" rev-parse HEAD)" = "$(git -C "$PRIVATE" rev-parse main)" ]
  git -C "$BASE" diff --quiet HEAD
}

@test "запись с текстом, похожим на ключ доступа, не сохраняется" {
  # Split so that this file holds no key-like string.
  run ! commit_note "$BASE" "key AKIA""TESTKEY000000000"
  [ "$(git -C "$BASE" rev-parse HEAD)" = "$(git -C "$PRIVATE" rev-parse main)" ]
}

@test "перезапись истории личной базы отклонена" {
  local pushed
  commit_note "$BASE" "обычная заметка"
  git -C "$BASE" push -q origin HEAD
  pushed="$(git -C "$PRIVATE" rev-parse main)"
  git -C "$BASE" commit -q --amend -m "test: rewritten history"
  run ! git -C "$BASE" push -q --force origin HEAD:main
  [ "$(git -C "$PRIVATE" rev-parse main)" = "$pushed" ]
}
