#!/usr/bin/env bats
# The Bash guard of the Claude Code adapter: which commands it refuses (exit 2) and
# which it lets through (exit 0). Quoted text, comments and heredoc bodies are data.
# The commands under test are literal text: a $ in them must not expand.
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0
load helpers

GUARD="$ROOT/adapters/claude/hooks/destructive-guard.sh"

guard() {
  bash_input "$ROOT" "$1" | "$GUARD"
}

# blocked <command...>: the guard refuses every command.
blocked() {
  local c rc bad=""
  for c in "$@"; do
    rc=0
    guard "$c" >/dev/null 2>&1 || rc=$?
    [ "$rc" = 2 ] || bad="$bad [$c -> $rc]"
  done
  [ -z "$bad" ] || {
    echo "не заблокированы:$bad"
    return 1
  }
}

# allowed <command...>: the guard lets every command through.
allowed() {
  local c rc bad=""
  for c in "$@"; do
    rc=0
    guard "$c" >/dev/null 2>&1 || rc=$?
    [ "$rc" = 0 ] || bad="$bad [$c -> $rc]"
  done
  [ -z "$bad" ] || {
    echo "заблокированы зря:$bad"
    return 1
  }
}

# core_guard <command>: the guard's core, which every agent's adapter feeds with plain text.
core_guard() {
  printf '%s\n' "$1" | sh "$ROOT/scripts/guard.sh"
}

@test "ядро защиты получает команду простым текстом: переходник любого агента передаёт её как есть" {
  run -2 core_guard "git add -A"
  [[ $output == *"git add -A"* ]]
  run -0 core_guard "git status"
}

@test "блокирует добавление всех файлов разом" {
  blocked "git add -A" "git add --all" "git add -u" "git add ." "git -C /work/project add -A" \
    "git status && git add ." "echo x; git add -A" 'x=$(git add -A)'
}

@test "пропускает добавление конкретных файлов" {
  allowed "git add README.md" "git add -- docs/a.md" "git -C /work/project add src/x.sh"
}

@test "блокирует перезапись истории и удаление в удалённом хранилище" {
  blocked "git push --force origin main" "git push -f" "git push -uf origin main" "git push origin +main" \
    "git push --mirror" "git push --delete origin feature" "git push -d origin feature" "git push origin :feature"
}

@test "пропускает обычную отправку и --force-with-lease" {
  allowed "git push" "git push -u origin main" "git push --force-with-lease origin main" "git push origin HEAD:main"
}

@test "блокирует git reset --hard и git clean -f" {
  blocked "git reset --hard" "git reset --hard HEAD~1" "git clean -fdx" "git clean -f" "git clean --force"
}

@test "пропускает мягкий сброс и пробную очистку" {
  allowed "git reset --soft HEAD~1" "git reset HEAD notes.md" "git clean -n" "git clean -fn" "git clean --dry-run -f"
}

@test "блокирует rm -r -f вне временных папок" {
  blocked "rm -rf /home/user/project" "rm -rf build" "rm -r -f build" "rm -fr ~/notes" \
    "rm --recursive --force build" "sudo rm -rf /var/lib/x" "rm -rf /tmp/../home/user" "rm -rf /tmp" \
    "find . -name '*.o' | xargs rm -rf"
}

@test "пропускает rm -r -f во временных папках и rm без одного из флагов" {
  allowed "rm -rf /tmp/build-123" 'rm -rf "$TMPDIR/x"' "rm -rf /tmp/x 2>/dev/null" "rm -f notes.txt" "rm -r build"
}

@test "блокирует gh repo delete" {
  blocked "gh repo delete me/repo --yes"
}

@test "блокирует переход в папку отдельной командой cd" {
  blocked "cd /tmp" "cd /tmp && ls" "ls && cd /work"
}

@test "пропускает cd в подоболочке и слово cd в тексте" {
  allowed "(cd /tmp && ls)" 'x=$(cd /tmp && pwd)' 'echo "cd /tmp"' "git commit -m 'cd into dir'" \
    'git commit -m "first line
cd second line"'
}

@test "текст в heredoc - данные, а не команды" {
  allowed "cat > notes.md <<'EOF'
rm -rf /
git add -A
EOF" "git commit -F - <<EOF
git push --force is forbidden
EOF"
}

@test "heredoc, который читает оболочка, проверяется" {
  blocked "bash <<'EOF'
git add -A
EOF" "cat <<EOF | sh
rm -rf /home/user
EOF"
}

@test "комментарии и строки в кавычках не блокируются" {
  allowed "# git add -A" "echo 'git push --force'" 'grep -r "rm -rf" docs' "printf '%s\n' \"git reset --hard\""
}

@test "непонятный вход блокируется" {
  run -2 "$GUARD" <<<"not json"
  run -2 "$GUARD" <<<'{"tool_input": {}}'
  run -2 "$GUARD" <<<'{"tool_input": {"command": ""}}'
}
