#!/bin/sh
# Texts the workbench hooks give an agent, the same for every agent. The adapter of each
# hook protocol reads the hook input, calls these functions and wraps the text the way its
# agent expects it. Source paths.sh first.

# wb_agent <hook input>: the agent that runs the hook. Cursor runs the hooks of Claude
# Code's settings itself and says so in the input and the environment; the Codex hooks
# name their agent in WB_AGENT; everything else is Claude Code.
wb_agent() {
  if [ -n "${CURSOR_PROJECT_DIR:-}" ] || printf '%s' "$1" | jq -e 'has("cursor_version")' >/dev/null 2>&1; then
    echo cursor
  else
    echo "${WB_AGENT:-claude}"
  fi
}

# wb_files_line <agent>: how the agent gets the base's instructions and memory. Only
# Claude Code imports files by reference. Codex and Cursor read the instructions
# themselves and get the memory index at the end of the session context: Codex was seen
# skipping both files although its user-level AGENTS.md asked for them.
wb_files_line() {
  wb_files="Инструкции workbench - ${WB_DIR}/AGENTS.md, личная память владельца - ${WB_DIR}/memory/MEMORY.md"
  wb_own="подключать файлы по ссылке не умеет: прочитай их в начале сессии; индекс памяти - в конце этого сообщения"
  case $1 in
    codex)
      wb_line="Инструкции workbench - ${WB_DIR}/AGENTS.md. Codex ${wb_own}."
      wb_codex_attached ||
        wb_line="${wb_line} Путей к базе в $(wb_codex_agents_md) нет: предложи владельцу подключить их командой workbench attach --user."
      ;;
    cursor)
      wb_line="Инструкции workbench - ${WB_DIR}/AGENTS.md. Cursor ${wb_own}."
      ;;
    *)
      if wb_user_attached; then
        wb_line="${wb_files}; Claude Code загружает их из $(wb_user_claude_md)."
      else
        wb_line="${wb_files}. В $(wb_user_claude_md) их нет: прочитай оба файла и предложи владельцу подключить их командой workbench attach --user (если команды нет в PATH: sh \"${WB_DIR}/bin/workbench\" attach --user)."
      fi
      ;;
  esac
  printf '%s\n' "$wb_line"
}

# wb_memory_index <agent>: the owner's memory index for an agent without imports.
wb_memory_index() {
  case $1 in
    codex | cursor) ;;
    *) return 0 ;;
  esac
  [ -f "$WB_DIR/memory/MEMORY.md" ] || return 0
  printf 'Индекс личной памяти владельца (%s, файлы памяти лежат рядом):\n' "$WB_DIR/memory/MEMORY.md"
  cat "$WB_DIR/memory/MEMORY.md"
}

# wb_layers_line <folder>: where the layers of knowledge live for the session's project:
# the personal LPF and DPFs in the base, the project's in lpf/ and dpf/ of its git.
wb_layers_line() {
  wb_layers="Слои знаний (раздел 3 в AGENTS.md): личные LPF и DPF - ${WB_DIR}/lpf/ и ${WB_DIR}/dpf/"
  wb_root="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$wb_root" ] && [ "$(cd "$wb_root" && pwd -P)" != "$WB_DIR" ]; then
    wb_found=""
    for wb_entry in "$wb_root"/lpf/*.md "$wb_root"/lpf/*/ "$wb_root"/dpf/*.md "$wb_root"/dpf/*/; do
      [ -e "$wb_entry" ] || continue
      # A README explains its folder; the frameworks are the other files and folders.
      case $wb_entry in */README.md) continue ;; esac
      wb_found="${wb_found} ${wb_entry#"$wb_root"/}"
    done
    if [ -n "$wb_found" ]; then
      wb_layers="${wb_layers}; проектные - в git проекта:${wb_found}"
    else
      wb_layers="${wb_layers}; проектных пока нет, их место - lpf/ и dpf/ в корне проекта"
    fi
  fi
  printf '%s.\n' "$wb_layers"
}

# wb_session_context <agent> <folder>: the date, the workbench and FPF locations, the sync
# state of the base, a warning about locally changed executable parts and the active work
# products. Read-only.
wb_session_context() {
  pinned="$(wb_fpf_edition commit)"
  if fpf_rev="$(git -C "$FPF_DIR" rev-parse HEAD 2>/dev/null)"; then
    fpf_line="\$FPF = ${FPF_DIR} (издание $(printf '%.7s' "$fpf_rev"))"
    [ "$fpf_rev" = "$pinned" ] ||
      fpf_line="${fpf_line}; ВНИМАНИЕ: закреплено издание $(printf '%.7s' "$pinned"), рабочую копию на него переводит sh ${WB_DIR}/scripts/setup.sh"
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

  cat <<EOF
workbench подключён. Сегодня $(date '+%Y-%m-%d %A').
Целевой проект: $2
\$WORKBENCH = ${WB_DIR} (git: ${sync_state#\#\# })
$(wb_files_line "$1")
$(wb_layers_line "$2")
${fpf_line}
${warn_line}
Активные РП (\$WORKBENCH/docs/WP-REGISTRY.md):
${active}
Правило допуска: свяжи задачу с РП и назови его ("Работаю по РП N: ..."). Подходящего нет - предложи принять, отложить, отклонить или вернуть (OPS.5); новый РП заводи скиллом wp-new только после явного "да".
Граница: в \$WORKBENCH пишется только личное (РП, личные решения, факты о владельце). Код, данные и факты целевого проекта - только в сам проект или во встроенную память агента для этого проекта, никогда в \$WORKBENCH.
EOF
  wb_memory_index "$1"
}

# wb_prompt: the owner's message taken from the hook input on stdin. Line breaks that an
# agent leaves raw inside the JSON string would make it invalid, so they count as spaces.
wb_prompt() {
  LC_ALL=C tr '\n\r\t' '   ' | jq -r '.prompt // empty' 2>/dev/null
}

# wb_prompt_answer <text>: the answer of a UserPromptSubmit hook in Claude Code's protocol:
# the text as context for the agent, or an empty object when there is nothing to add.
wb_prompt_answer() {
  if [ -n "$1" ]; then
    jq -n --arg ctx "$1" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
  else
    echo '{}'
  fi
}

wb_wp_reminder() {
  printf '%s\n' "РП: новую задачу свяжи с РП из ${WB_DIR}/docs/WP-REGISTRY.md (нет подходящего - принять, отложить, отклонить или вернуть, OPS.5). Продолжение того же РП - продолжай. Вопрос без изменения файлов РП не требует."
}

# wb_close_reminder <prompt>: the close instruction when the prompt asks to close the session.
wb_close_reminder() {
  # tr '[:upper:]' '[:lower:]' is byte-based and misses Cyrillic capitals ("Закрывай"),
  # so match case-insensitively in a UTF-8 locale instead.
  if printf '%s' "$1" | LC_ALL=C.UTF-8 grep -qiE '(закрывай|закрываю|закрываем|закрой сессию)'; then
    printf '%s\n' "Закрытие: первым действием вызови скилл close-session и пройди его шаги по порядку, ничего не пропуская."
  fi
}
