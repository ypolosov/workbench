#!/usr/bin/env bats
# Rules for the workbench's own code. Linting and formatting: make lint, make format-check.

load helpers

@test "в файлах шаблона только символы с клавиатуры: ASCII и русские буквы" {
  # A perl program, not shell text.
  # shellcheck disable=SC2016
  bad="$(cd "$ROOT" && git ls-files -co --exclude-standard -z |
    xargs -0 perl -CSD -ne 'chomp; print "$ARGV:$.\n" if /[^\t\x20-\x7E\x{0400}-\x{04FF}]/; close ARGV if eof' 2>/dev/null)"
  [ -z "$bad" ] || {
    echo "символы вне клавиатуры:"
    echo "$bad"
    return 1
  }
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
