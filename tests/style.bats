#!/usr/bin/env bats
# Rules for the workbench's own code. Linting and formatting: make lint, make format-check.

load helpers

@test "в файлах шаблона только символы с клавиатуры: ASCII и русские буквы" {
  bad="$(off_keyboard "$ROOT")"
  [ -z "$bad" ] || {
    echo "символы вне клавиатуры:"
    echo "$bad"
    return 1
  }
}

@test "проверка символов пропускает двоичные файлы и находит символ вне клавиатуры в тексте" {
  # Only this repository's files count: global git ignores stay out.
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig" GIT_CONFIG_NOSYSTEM=1
  dir="$BATS_TEST_TMPDIR/chars"
  git init -q "$dir"
  printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000' >"$dir/image.png"
  printf 'plain text\n' >"$dir/plain.md"
  printf 'dash \342\200\224 here\n' >"$dir/dash.md"
  run off_keyboard "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "dash.md:1" ]
}

@test "все скрипты вне тестов написаны на POSIX sh (#!/bin/sh)" {
  bad=""
  while IFS= read -r f; do
    [ -f "$ROOT/$f" ] || continue
    first="$(head -n 1 "$ROOT/$f")"
    case $first in
      '#!/bin/sh') ;;
      '#!'*) bad="$bad $f" ;;
    esac
  done < <(git -C "$ROOT" ls-files -co --exclude-standard -- . ':!tests')
  [ -z "$bad" ] || {
    echo "не POSIX sh:$bad"
    return 1
  }
}
