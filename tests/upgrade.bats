#!/usr/bin/env bats
# Program updates import the published history without committing personal work.
bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  make_sandbox
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
}

setup() {
  export SOURCE="$SANDBOX/source-$BATS_TEST_NUMBER" BASE="$SANDBOX/base-$BATS_TEST_NUMBER"
  git clone -q "$TPL" "$SOURCE"
  printf 'old first\n\n2\n3\n4\n5\n6\n7\n8\n9\n10\n\nold last\n' >"$SOURCE/scripts/update-probe.txt"
  git -C "$SOURCE" add scripts/update-probe.txt
  git -C "$SOURCE" commit -qm "published old program"
  git clone -q "$SOURCE" "$BASE"
  git -C "$BASE" config core.hooksPath .githooks
  mkdir -p "$BASE/.runtime"
  git -C "$SOURCE" rev-parse HEAD >"$BASE/.runtime/program-version"
  printf 'committed personal memory\n' >"$BASE/memory/personal.md"
  git -C "$BASE" add memory/personal.md
  git -C "$BASE" commit -qm "personal memory"
  BEFORE="$(git -C "$BASE" rev-parse HEAD)"
  export BEFORE
  sed 's/old first/new first/' "$SOURCE/scripts/update-probe.txt" >"$SANDBOX/new-probe"
  cp "$SANDBOX/new-probe" "$SOURCE/scripts/update-probe.txt"
  printf '\nPublished program update.\n' >>"$SOURCE/README.md"
  printf 'template memory\n' >"$SOURCE/memory/template-only.md"
  printf '\nTemplate practice must not replace personal practice.\n' >>"$SOURCE/lpf/README.md"
  git -C "$SOURCE" add scripts/update-probe.txt README.md memory/template-only.md lpf/README.md
  git -C "$SOURCE" commit -qm "published new program"
}

upgrade() {
  # shellcheck disable=SC2016
  sh -c 'WB_DIR=$1; . "$2/scripts/upgrade.sh"; wb_upgrade_program "$2"' sh "$BASE" "$SOURCE"
}

@test "обновление записывает историю шаблона и оставляет личные файлы и индекс как были" {
  printf 'staged personal memory\n' >"$BASE/memory/personal.md"
  git -C "$BASE" add memory/personal.md
  printf 'unstaged personal memory\n' >>"$BASE/memory/personal.md"
  printf 'untracked personal note\n' >"$BASE/inbox/owner-only.md"
  git -C "$BASE" diff --cached --binary >"$SANDBOX/index-before"
  cp "$BASE/memory/personal.md" "$SANDBOX/memory-before"
  cp "$BASE/lpf/README.md" "$SANDBOX/practice-before"
  run -0 upgrade
  git -C "$BASE" merge-base --is-ancestor "$(git -C "$SOURCE" rev-parse HEAD)" HEAD
  git -C "$BASE" merge-base --is-ancestor "$BEFORE" HEAD
  git -C "$BASE" diff --quiet HEAD -- bin scripts adapters .githooks README.md
  git -C "$BASE" diff --cached --binary | cmp - "$SANDBOX/index-before"
  cmp "$BASE/memory/personal.md" "$SANDBOX/memory-before"
  cmp "$BASE/lpf/README.md" "$SANDBOX/practice-before"
  [ ! -e "$BASE/memory/template-only.md" ]
  run ! git -C "$BASE" cat-file -e HEAD:inbox/owner-only.md
  run -0 git -C "$BASE" show HEAD:memory/personal.md
  [[ $output != *'staged personal'* ]]
}

@test "обновление принимает ранее скопированную программу без незакоммиченных файлов" {
  cp "$SOURCE/scripts/update-probe.txt" "$BASE/scripts/update-probe.txt"
  cp "$SOURCE/README.md" "$BASE/README.md"
  printf '#!/bin/sh\nprintf "new command\\n"\n' >"$SOURCE/scripts/new-command.sh"
  chmod +x "$SOURCE/scripts/new-command.sh"
  git -C "$SOURCE" add scripts/new-command.sh
  git -C "$SOURCE" commit -qm "published new command"
  cp "$SOURCE/scripts/new-command.sh" "$BASE/scripts/new-command.sh"
  git -C "$BASE" add README.md
  run -0 upgrade
  git -C "$BASE" diff --quiet HEAD -- bin scripts adapters .githooks README.md
  git -C "$BASE" diff --cached --quiet
  [ -z "$(git -C "$BASE" ls-files --others --exclude-standard scripts)" ]
}

@test "повторное обновление той же версии не создаёт коммит" {
  run -0 upgrade
  saved="$(git -C "$BASE" rev-parse HEAD)"
  run -0 upgrade
  [ "$(git -C "$BASE" rev-parse HEAD)" = "$saved" ]
  [ "$(cat "$BASE/.runtime/program-version")" = "$(git -C "$SOURCE" rev-parse HEAD)" ]
}

@test "местная правка программы остаётся незакоммиченной после обновления" {
  sed 's/old last/owner last/' "$BASE/scripts/update-probe.txt" >"$SANDBOX/owner-probe"
  cp "$SANDBOX/owner-probe" "$BASE/scripts/update-probe.txt"
  run -0 upgrade
  grep -q '^new first$' "$BASE/scripts/update-probe.txt"
  grep -q '^owner last$' "$BASE/scripts/update-probe.txt"
  git -C "$BASE" show HEAD:scripts/update-probe.txt | grep -q '^old last$'
  [ "$(git -C "$BASE" status --porcelain -- scripts/update-probe.txt)" = ' M scripts/update-probe.txt' ]
}

@test "раздельные подготовленные и неподготовленные правки программы сохраняют своё состояние" {
  sed 's/old last/staged last/' "$BASE/scripts/update-probe.txt" >"$SANDBOX/staged-probe"
  cp "$SANDBOX/staged-probe" "$BASE/scripts/update-probe.txt"
  git -C "$BASE" add scripts/update-probe.txt
  printf '\nunstaged owner text\n' >>"$BASE/scripts/update-probe.txt"
  run -0 upgrade
  git -C "$BASE" show :scripts/update-probe.txt | grep -q '^new first$'
  git -C "$BASE" show :scripts/update-probe.txt | grep -q '^staged last$'
  run -0 git -C "$BASE" show :scripts/update-probe.txt
  [[ $output != *'unstaged owner text'* ]]
  grep -q '^unstaged owner text$' "$BASE/scripts/update-probe.txt"
  [ "$(git -C "$BASE" status --porcelain -- scripts/update-probe.txt)" = 'MM scripts/update-probe.txt' ]
}

@test "сохранённая местная правка программы объединяется с историей шаблона" {
  sed 's/old last/committed owner last/' "$BASE/scripts/update-probe.txt" >"$SANDBOX/committed-probe"
  cp "$SANDBOX/committed-probe" "$BASE/scripts/update-probe.txt"
  git -C "$BASE" add scripts/update-probe.txt
  git -C "$BASE" commit -qm "owner program customization"
  run -0 upgrade
  grep -q '^new first$' "$BASE/scripts/update-probe.txt"
  grep -q '^committed owner last$' "$BASE/scripts/update-probe.txt"
  git -C "$BASE" diff --quiet HEAD -- scripts/update-probe.txt
}

@test "конфликт оставляет историю, индекс и все исходные файлы без изменений" {
  sed 's/old first/owner first/' "$BASE/scripts/update-probe.txt" >"$SANDBOX/conflict-probe"
  cp "$SANDBOX/conflict-probe" "$BASE/scripts/update-probe.txt"
  cp "$BASE/scripts/update-probe.txt" "$SANDBOX/conflict-before"
  git -C "$BASE" diff --cached --binary >"$SANDBOX/conflict-index"
  run -1 upgrade
  [ "$(git -C "$BASE" rev-parse HEAD)" = "$BEFORE" ]
  cmp "$BASE/scripts/update-probe.txt" "$SANDBOX/conflict-before"
  run ! grep -q 'Published program update' "$BASE/README.md"
  git -C "$BASE" diff --cached --binary | cmp - "$SANDBOX/conflict-index"
  [ "$(git -C "$BASE" worktree list --porcelain | grep -c '^worktree ')" = 1 ]
}

@test "обновление удаляет снятые с поставки файлы программы" {
  git -C "$SOURCE" rm -q scripts/update-probe.txt
  git -C "$SOURCE" commit -qm "remove retired program file"
  run -0 upgrade
  [ ! -e "$BASE/scripts/update-probe.txt" ]
  git -C "$BASE" diff --quiet HEAD -- scripts
}

@test "чужой неподготовленный файл не заменяется новым файлом поставки" {
  printf '#!/bin/sh\nprintf "published\\n"\n' >"$SOURCE/scripts/new-command.sh"
  git -C "$SOURCE" add scripts/new-command.sh
  git -C "$SOURCE" commit -qm "new command"
  printf 'owner untracked file\n' >"$BASE/scripts/new-command.sh"
  run -1 upgrade
  [ "$(git -C "$BASE" rev-parse HEAD)" = "$BEFORE" ]
  [ "$(cat "$BASE/scripts/new-command.sh")" = 'owner untracked file' ]
}

@test "отказ проверки коммита останавливает обновление без обхода хука" {
  mkdir -p "$SANDBOX/reject-hook"
  printf '#!/bin/sh\nprintf "checked\\n" >"%s"\nexit 1\n' "$SANDBOX/hook-called" >"$SANDBOX/reject-hook/pre-commit"
  chmod +x "$SANDBOX/reject-hook/pre-commit"
  git -C "$BASE" config core.hooksPath "$(native "$SANDBOX/reject-hook")"
  run -1 upgrade
  [ -f "$SANDBOX/hook-called" ]
  [ "$(git -C "$BASE" rev-parse HEAD)" = "$BEFORE" ]
  grep -q '^old first$' "$BASE/scripts/update-probe.txt"
}

@test "обновление не требует настройки авторства Git на чистой машине" {
  git config --global --unset user.name
  git config --global --unset user.email
  run upgrade
  git config --global user.name "workbench test"
  git config --global user.email "test@example.invalid"
  [ "$status" = 0 ]
  git -C "$BASE" merge-base --is-ancestor "$(git -C "$SOURCE" rev-parse HEAD)" HEAD
}

@test "обновление принимает имена файлов программы с кириллицей и пробелами" {
  printf 'published program file\n' >"$SOURCE/scripts/проверка обновления.txt"
  git -C "$SOURCE" add 'scripts/проверка обновления.txt'
  git -C "$SOURCE" commit -qm "published file with a Unicode name"
  run -0 upgrade
  [ "$(cat "$BASE/scripts/проверка обновления.txt")" = 'published program file' ]
  git -C "$BASE" diff --quiet HEAD -- scripts
}

@test "обновление распознаёт старую скопированную версию даже без записи установщика" {
  cp "$SOURCE/scripts/update-probe.txt" "$BASE/scripts/update-probe.txt"
  rm -f "$BASE/.runtime/program-version"
  sed 's/new first/newer first/' "$SOURCE/scripts/update-probe.txt" >"$SANDBOX/newer-probe"
  cp "$SANDBOX/newer-probe" "$SOURCE/scripts/update-probe.txt"
  git -C "$SOURCE" add scripts/update-probe.txt
  git -C "$SOURCE" commit -qm "published newer program"
  run -0 upgrade
  grep -q '^newer first$' "$BASE/scripts/update-probe.txt"
  git -C "$BASE" diff --quiet HEAD -- scripts
}
