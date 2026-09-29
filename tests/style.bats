#!/usr/bin/env bats
# Rules for the workbench's own code. Linting and formatting: make lint, make format-check.

load helpers

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
