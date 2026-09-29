#!/bin/sh
# WP gate reminder (UserPromptSubmit). Adapted from FMT-exocortex-template
# .claude/hooks/wp-gate-reminder.sh (MIT, Tseren Tserenov): platform-specific
# Day Open branch removed, text points to the workbench registry.
# Read-only: returns additionalContext JSON only.

cat >/dev/null
ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
CTX="РП: новую задачу свяжи с РП из ${ROOT}/docs/WP-REGISTRY.md (нет подходящего - принять, отложить, отклонить или вернуть, OPS.5). Продолжение того же РП - продолжай. Вопрос без изменения файлов РП не требует."
jq -n --arg ctx "$CTX" '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": $ctx}}'
exit 0
