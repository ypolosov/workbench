#!/bin/sh
# SessionStart hook (Claude Code adapter): puts the date, workbench and FPF
# locations, the workbench sync state, a warning about locally changed
# executable parts and the active work products into the session context.
# Read-only; never fails the session.
set -u

WB_DIR="$(cd "$(dirname "$0")/../../.." && pwd -P)"
# shellcheck source=../../../scripts/paths.sh
. "$WB_DIR/scripts/paths.sh"

input="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
cwd="${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}"

pinned="$(wb_fpf_edition commit)"
if fpf_rev="$(git -C "$FPF_DIR" rev-parse HEAD 2>/dev/null)"; then
  fpf_line="\$FPF = ${FPF_DIR} (издание $(printf '%.7s' "$fpf_rev"))"
  [ "$fpf_rev" = "$pinned" ] || fpf_line="${fpf_line}; ВНИМАНИЕ: закреплено издание $(printf '%.7s' "$pinned")"
else
  fpf_line="\$FPF не подготовлен: запусти ${WB_DIR}/scripts/setup.sh"
fi

sync_state="$(git -C "$WB_DIR" status -sb 2>/dev/null | head -n 1)"
# Hooks, scripts and skills run in every session: local edits nobody saved may be tampering.
changed="$(git -C "$WB_DIR" status --porcelain -- adapters scripts .githooks .agents 2>/dev/null | tr '\n' ' ')"
if [ -n "$changed" ]; then
  warn_line="ВНИМАНИЕ: в workbench есть несохранённые изменения исполняемых частей (хуки, скрипты, скиллы): ${changed}. Прежде чем продолжать, покажи это владельцу."
else
  warn_line="Исполняемые части workbench совпадают с сохранёнными."
fi

registry="$WB_DIR/docs/WP-REGISTRY.md"
active="$(grep -E '^\| *[0-9]+ *\|' "$registry" 2>/dev/null | grep -E '\| *(in_progress|pending|deferred) *\|' || true)"
[ -n "$active" ] || active="(активных РП нет)"

ctx="workbench подключён. Сегодня $(date '+%Y-%m-%d %A').
Целевой проект: ${cwd}
\$WORKBENCH = ${WB_DIR} (git: ${sync_state#\#\# })
${fpf_line}
${warn_line}
Активные РП (\$WORKBENCH/docs/WP-REGISTRY.md):
${active}
Правило допуска: свяжи задачу с РП и назови его («Работаю по РП N: …»). Подходящего нет - предложи принять, отложить, отклонить или вернуть (OPS.5); новый РП заводи скиллом wp-new только после явного «да».
Граница: в \$WORKBENCH пишется только личное (РП, личные решения, факты о владельце). Код, данные и факты целевого проекта - только в сам проект или во встроенную память агента для этого проекта, никогда в \$WORKBENCH."

jq -n --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
