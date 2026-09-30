#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  make_sandbox
  export BASE="$SANDBOX/my base" P1="$SANDBOX/project-one" USER_MD="$HOME/.claude/CLAUDE.md"
  bootstrap "$BASE" --repo "$PRIVATE"
  new_project "$P1"
  wb "$P1" attach
  mkdir -p "$HOME/.claude"
  printf '# Мои правила для всех проектов\n\nОтвечать по-русски.\n' >"$USER_MD"
  cp "$USER_MD" "$SANDBOX/user-md.orig"
  wb "$SANDBOX" attach --user
}

import_path() {
  sed -n 's/^@//p' "$USER_MD" | sed -n "${1}p" | sed 's/\\ / /g'
}

@test "attach --user дописывает блок workbench к пользовательскому CLAUDE.md, свой текст владельца сохранён" {
  head -n 3 "$USER_MD" | cmp - "$SANDBOX/user-md.orig"
  [ "$(grep -c '^<!-- workbench:user begin' "$USER_MD")" = 1 ]
}

@test "блок импортирует инструкции и личную память самой базы" {
  [ "$(grep -c '^@' "$USER_MD")" = 2 ]
  cmp "$(import_path 1)" "$BASE/AGENTS.md"
  cmp "$(import_path 2)" "$BASE/memory/MEMORY.md"
}

@test "пробелы в пути к базе экранированы в импортах" {
  grep -qF 'my\ base/AGENTS.md' "$USER_MD"
  grep -qF 'my\ base/memory/MEMORY.md' "$USER_MD"
}

@test "блок называет личную базу этой машины" {
  same_dir "$(sed -n 's/^- [$]WORKBENCH = \(.*\) (личная база этой машины)$/\1/p' "$USER_MD")" "$BASE"
}

@test "повторный attach --user не задваивает блок" {
  wb "$SANDBOX" attach --user
  [ "$(grep -c '^<!-- workbench:user begin' "$USER_MD")" = 1 ]
  head -n 3 "$USER_MD" | cmp - "$SANDBOX/user-md.orig"
}

@test "с блоком начало сессии не просит читать файлы базы вручную" {
  ctx="$(session_context "$P1")"
  [[ $ctx == *"$BASE/AGENTS.md"* ]]
  [[ $ctx != *"прочитай оба файла"* ]]
}

@test "с блоком подключение проекта не подсказывает attach --user" {
  new_project "$SANDBOX/p-with-user"
  run -0 wb "$SANDBOX/p-with-user" attach
  [[ $output != *"attach --user"* ]]
}

@test "блок с импортом из другой папки не считается подключением этой базы" {
  cp "$USER_MD" "$SANDBOX/user-md.current"
  sed 's#^@.*/AGENTS.md$#@/elsewhere/AGENTS.md#' "$SANDBOX/user-md.current" >"$USER_MD"
  ctx="$(session_context "$P1")"
  cp "$SANDBOX/user-md.current" "$USER_MD"
  [[ $ctx == *"прочитай оба файла"* ]]
}

@test "detach --user убирает блок, свой текст владельца остаётся как был" {
  wb "$SANDBOX" detach --user
  cmp "$USER_MD" "$SANDBOX/user-md.orig"
}

@test "без блока начало сессии просит прочитать файлы базы и называет команду" {
  ctx="$(session_context "$P1")"
  [[ $ctx == *"$BASE/AGENTS.md"* ]]
  [[ $ctx == *"$BASE/memory/MEMORY.md"* ]]
  [[ $ctx == *"прочитай оба файла"* ]]
  [[ $ctx == *"workbench attach --user"* ]]
}

@test "detach --user без блока - понятная ошибка" {
  run -1 wb "$SANDBOX" detach --user
  [[ $output == *"$USER_MD"* ]]
}

@test "attach --user создаёт пользовательский CLAUDE.md, если его нет, а detach --user его убирает" {
  rm "$USER_MD"
  wb "$SANDBOX" attach --user
  grep -q '^<!-- workbench:user begin' "$USER_MD"
  wb "$SANDBOX" detach --user
  [ ! -e "$USER_MD" ]
}

@test "с CLAUDE_CONFIG_DIR блок пишется в CLAUDE.md этой папки" {
  (
    export CLAUDE_CONFIG_DIR="$SANDBOX/claude-config"
    wb "$SANDBOX" attach --user
  )
  grep -q '^<!-- workbench:user begin' "$SANDBOX/claude-config/CLAUDE.md"
  [ ! -e "$USER_MD" ]
}

@test "пользовательский CLAUDE.md - ссылка на файл из dotfiles: ссылка остаётся, блок уходит в сам файл" {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) skip "Git Bash без режима разработчика делает вместо ссылки на файл копию" ;;
  esac
  mkdir -p "$SANDBOX/dotfiles"
  printf '# dotfiles\n' >"$SANDBOX/dotfiles/CLAUDE.md"
  ln -s "$SANDBOX/dotfiles/CLAUDE.md" "$USER_MD"
  wb "$SANDBOX" attach --user
  [ -L "$USER_MD" ]
  grep -q '^<!-- workbench:user begin' "$SANDBOX/dotfiles/CLAUDE.md"
  wb "$SANDBOX" detach --user
  [ -L "$USER_MD" ]
  [ "$(cat "$SANDBOX/dotfiles/CLAUDE.md")" = "# dotfiles" ]
}
