#!/usr/bin/env bats
# Layers of knowledge: the personal LPF and DPFs live in the base, the project's LPF and
# DPFs in the project's own git (lpf/ and dpf/ at its root). The session start names both,
# so the agent knows where knowledge goes; the skills keep a form every agent accepts.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  make_sandbox
  export BASE="$SANDBOX/my-workbench" P1="$SANDBOX/project-one" P2="$SANDBOX/project-two"
  bootstrap "$BASE" --repo "$PRIVATE"
  new_project "$P1"
  mkdir -p "$P1/lpf" "$P1/dpf"
  printf '# Team Practice Framework\n' >"$P1/lpf/team-practice.md"
  printf '# Platform Principles Framework\n' >"$P1/dpf/platform.md"
  wb "$P1" attach
  new_project "$P2"
  wb "$P2" attach
}

@test "начало сессии называет LPF и DPF проекта" {
  ctx="$(session_context "$P1")"
  [[ $ctx == *"lpf/team-practice.md"* ]]
  [[ $ctx == *"dpf/platform.md"* ]]
}

@test "в проекте без LPF и DPF начало сессии говорит, куда их класть" {
  ctx="$(session_context "$P2")"
  [[ $ctx == *"lpf/ и dpf/"* ]]
}

@test "начало сессии называет личные LPF и DPF в базе" {
  ctx="$(session_context "$P2")"
  [[ $ctx == *"$(native "$BASE")/lpf/"* ]]
  [[ $ctx == *"$(native "$BASE")/dpf/"* ]]
}

@test "у каждого скилла базы имя совпадает с папкой и есть описание: так их принимают Codex и Cursor" {
  bad=""
  for skill in "$BASE"/.agents/skills/*/; do
    dir="$(basename "$skill")"
    name="$(sed -n '2,/^---$/s/^name: *//p' "$skill/SKILL.md" | head -n 1)"
    grep -q '^description: ' "$skill/SKILL.md" || bad="$bad $dir(description)"
    [ "$name" = "$dir" ] || bad="$bad $dir(name=$name)"
  done
  [ -z "$bad" ] || {
    echo "не так:$bad"
    return 1
  }
}

@test "есть скилл разбора источника по слоям" {
  [ -f "$BASE/.agents/skills/distill/SKILL.md" ]
}
