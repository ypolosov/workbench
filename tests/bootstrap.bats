#!/usr/bin/env bats
# Bootstrap: the personal base of a machine is created from the template when its private
# repository is empty, or cloned when the repository already exists; the workbench
# command is installed. Tests run in file order.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  make_sandbox
  export BASE="$SANDBOX/machine-one/my-workbench" BASE2="$SANDBOX/machine-two/my-workbench"
  mkdir "$SANDBOX/machine-one" "$SANDBOX/machine-two"
  bootstrap "$BASE" --repo "$PRIVATE"
}

@test "личная база создана из шаблона и отправлена в закрытое хранилище" {
  [ "$(git -C "$PRIVATE" rev-parse main)" = "$(git -C "$TPL" rev-parse HEAD)" ]
  [ "$(git -C "$BASE" rev-parse HEAD)" = "$(git -C "$PRIVATE" rev-parse main)" ]
}

@test "у базы два адреса: личное хранилище (origin) и шаблон (template)" {
  remotes_ok "$BASE"
}

@test "FPF: рабочая копия на закреплённом издании" {
  [ "$(git -C "$BASE/.fpf" rev-parse HEAD)" = "$FPF_PINNED" ]
}

@test "FPF: скачана одна ревизия, без истории и новых изданий" {
  only_pinned_fetched "$BASE"
}

@test "FPF: рабочая копия заперта" {
  git -C "$BASE" worktree list --porcelain | grep -q '^locked'
}

@test "FPF: ссылка .fpf/.git относительная" {
  grep -q '^gitdir: \.\./\.git/worktrees/' "$BASE/.fpf/.git"
}

@test "команда workbench установлена и знает, где база" {
  run -0 "$SANDBOX/bin/workbench" help
  [[ $output == *"$(native "$BASE")"* ]]
  [[ $output == *attach* ]]
  [[ $output == *detach* ]]
}

@test "повторная установка в ту же папку обновляет базу и ничего не ломает" {
  bootstrap "$BASE"
  [ -z "$(git -C "$BASE" status --porcelain)" ]
  [ "$(git -C "$BASE/.fpf" rev-parse HEAD)" = "$FPF_PINNED" ]
}

@test "на второй машине установка клонирует существующую базу, даже когда HEAD хранилища указывает на отсутствующую ветку" {
  # `git init --bare` leaves HEAD at master where master is the default branch.
  git -C "$PRIVATE" symbolic-ref HEAD refs/heads/master
  bootstrap "$BASE2" --repo "$PRIVATE" --bin-dir "$SANDBOX/bin2"
  [ "$(git -C "$BASE2" rev-parse --abbrev-ref HEAD)" = main ]
  [ "$(git -C "$BASE2" rev-parse HEAD)" = "$(git -C "$PRIVATE" rev-parse main)" ]
  remotes_ok "$BASE2"
  [ "$(git -C "$BASE2/.fpf" rev-parse HEAD)" = "$FPF_PINNED" ]
}

@test "запись с одной машины доходит до другой через удалённое хранилище" {
  commit_note "$BASE" "заметка с первой машины"
  git -C "$BASE" push -q origin HEAD
  bootstrap "$BASE2" --bin-dir "$SANDBOX/bin2"
  grep -qxF "заметка с первой машины" "$BASE2/inbox/fleeting-notes.md"
}

@test "обновление шаблона подтягивается в базу с её собственными записями командой из подсказки" {
  commit_note "$BASE" "своя запись в базе"
  printf 'новое в шаблоне\n' >"$TPL/TEMPLATE-NEWS.md"
  git -C "$TPL" add TEMPLATE-NEWS.md
  git -C "$TPL" commit -qm "template: news"
  git -C "$BASE" pull -q template main
  [ -f "$BASE/TEMPLATE-NEWS.md" ]
  grep -qxF "своя запись в базе" "$BASE/inbox/fleeting-notes.md"
}
