#!/usr/bin/env bats
# The private base opened on its own, e.g. ~/DEV/GITS/my-workbench: setup.sh connects
# Claude Code, Cursor and Codex to the clone itself with local files that git ignores.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  make_sandbox
  export BASE="$SANDBOX/my-workbench"
  bootstrap "$BASE" --repo "$PRIVATE"
}

@test "CLAUDE.local.md подключает инструкции самой базы" {
  grep -qxF @AGENTS.md "$BASE/CLAUDE.local.md"
}

@test "начало сессии в самой базе указывает на неё" {
  ctx="$(session_context "$BASE")"
  [[ $ctx == *"\$WORKBENCH = $BASE"* ]]
}

@test "Codex в самой базе получает хуки базы" {
  jq -e '.hooks.PreToolUse[0].matcher == "^Bash$"' "$BASE/.codex/hooks.json"
  out="$(codex_hook "$BASE" session-start.sh "$(session_input "$BASE")")"
  [[ $(context_of "$out") == *"\$WORKBENCH = $BASE"* ]]
}

@test "повторный setup.sh не задваивает хуки Codex в самой базе, свой хук владельца остаётся" {
  jq '.hooks.Stop = [{hooks: [{type: "command", command: "true"}]}]' "$BASE/.codex/hooks.json" >"$SANDBOX/codex-own.json"
  cp "$SANDBOX/codex-own.json" "$BASE/.codex/hooks.json"
  sh "$BASE/scripts/setup.sh" >/dev/null
  jq -e '(.hooks.SessionStart | length) == 1 and (.hooks.SessionStart[0].hooks | length) == 1
    and (.hooks.Stop[0].hooks[0].command == "true")' "$BASE/.codex/hooks.json"
}

@test "скиллы базы доступны" {
  for skill in "$BASE"/.agents/skills/*/; do
    [ -f "$BASE/.claude/skills/$(basename "$skill")/SKILL.md" ]
  done
}

@test "git базы не видит файлы подключения" {
  [ -z "$(git -C "$BASE" status --porcelain)" ]
}
