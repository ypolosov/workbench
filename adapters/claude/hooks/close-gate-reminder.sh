#!/bin/sh
# Close gate reminder (UserPromptSubmit). Adapted from FMT-exocortex-template
# .claude/hooks/close-gate-reminder.sh (MIT, Tseren Tserenov): points to the
# close-session skill of this project instead of /run-protocol.
# Read-only: returns additionalContext JSON only.

INPUT=$(cat)
# Multiline prompts carry literal control chars that break jq; flatten them first.
SANITIZED=$(printf '%s' "$INPUT" | LC_ALL=C tr '\n\r\t' '   ')
PROMPT=$(printf '%s' "$SANITIZED" | jq -r '.prompt // empty')

# tr '[:upper:]' '[:lower:]' is byte-based and misses Cyrillic capitals ("Закрывай"),
# so match case-insensitively in a UTF-8 locale instead.
if printf '%s' "$PROMPT" | LC_ALL=C.UTF-8 grep -qiE '(закрывай|закрываю|закрываем|закрой сессию)'; then
  CTX="Закрытие: первым действием вызови скилл close-session и пройди его шаги по порядку, ничего не пропуская."
  jq -n --arg ctx "$CTX" '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": $ctx}}'
else
  echo '{}'
fi
exit 0
