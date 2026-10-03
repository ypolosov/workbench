#!/usr/bin/env bats
# The practice of the workbench rests on FPF: its skills, hooks and texts carry neither
# code nor text of the earlier IWE template, and stages of work have their own skill.

load helpers

@test "в практике шаблона нет наследия IWE" {
  bad="$(cd "$ROOT" && {
    # Section 7 of AGENTS.md holds the owner's own rules: they may name anything.
    awk '/^## 7\./ { exit } { print "AGENTS.md:" FNR ":" $0 }' AGENTS.md
    git ls-files -co --exclude-standard -z -- README.md lpf/README.md install.sh Makefile \
      .agents/skills scripts adapters/claude/hooks .githooks bin .github |
      xargs -0 grep -Hn ''
  } | grep -E 'IWE|FMT-exocortex|Tserenov|(^|[^a-z])vdv([^a-z]|$)|DP\.SC\.|PD\.METHOD|Day Open|ВДВ' |
    # The owner may still ask for stages by the old name of the method.
    grep -vE '^\.agents/skills/stages/SKILL\.md:[0-9]+:.*ВДВ' || true)"
  [ -z "$bad" ] || {
    echo "наследие IWE:"
    echo "$bad"
    return 1
  }
}

@test "есть скилл этапов работы" {
  [ -f "$ROOT/.agents/skills/stages/SKILL.md" ]
}
