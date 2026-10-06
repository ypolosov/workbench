#!/bin/sh
# workbench installer (bootstrap): makes the personal base of this machine and installs
# the workbench command. Run it anywhere:
#
#   curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh
#
# The base is the only local clone of the owner's private repository on this machine;
# when that repository is empty or missing, it is created from the public template.
# Running the installer again for the same folder updates the base. Afterwards,
# `workbench attach --user` points Claude Code and Codex to the base's instructions and
# memory in every project, and `workbench attach` in a project's folder adds the base's
# hooks and skills for Claude Code, Codex and Cursor.
set -eu

TEMPLATE="${WORKBENCH_TEMPLATE:-https://github.com/ypolosov/workbench.git}"
REPO="${WORKBENCH_REPO:-}"
SPACE="${WORKBENCH_SPACE:-}"
NAME="${WORKBENCH_NAME:-my-workbench}"
DIR="${WORKBENCH_DIR:-}"
BIN_DIR="${WORKBENCH_BIN_DIR:-$HOME/.local/bin}"
ASSUME_YES="${WORKBENCH_YES:-0}"
LOCAL=0
CORE_ONLY=0
PROJECT=""
NO_LAUNCH=0
STAGING=""
UI=0
INSTALL_CWD=$PWD

usage() {
  cat <<'EOF'
Установка workbench на эту машину.

  curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh -s -- \
    --repo git@gitlab.com:you/my-workbench.git --dir ~/my-workbench

Параметры (в скобках - переменные окружения):
  --repo URL      закрытое хранилище личной базы                          [WORKBENCH_REPO]
  --space URL     пространство для нового хранилища,                       [WORKBENCH_SPACE]
                  например git@gitlab.com:you или https://gitlab.com/you
  --name NAME     имя хранилища вместе с --space, по умолчанию my-workbench [WORKBENCH_NAME]
  --dir PATH      каталог workbench, по умолчанию найденный или ~/<имя>    [WORKBENCH_DIR]
  --bin-dir PATH  куда поставить команду workbench, по умолчанию ~/.local/bin [WORKBENCH_BIN_DIR]
  --template URL  публичный шаблон, по умолчанию                           [WORKBENCH_TEMPLATE]
                  https://github.com/ypolosov/workbench.git
  --local         новая личная база без обязательной регистрации в облаке
  --project PATH  сразу подключить проект
  --no-launch     завершить после диагностики, не открывать готовую оболочку
  --core-only     подготовить только базу (для управляемых окружений)
  --yes           использовать выбранные настройки без вопросов    [WORKBENCH_YES=1]
  -h, --help      эта справка

Без параметров установщик спрашивает всё в терминале. Существующий workbench
используется повторно. Личная папка хранит память, рабочие продукты и решения.
EOF
}

say() {
  printf 'workbench: %s\n' "$*" >&2
}

die() {
  say "$*"
  exit 1
}

# Answers come from the terminal: under curl | sh, stdin is the script itself.
have_tty() {
  (: </dev/tty) 2>/dev/null
}

interactive() {
  [ "$ASSUME_YES" != 1 ] && have_tty
}

# ask <prompt> [default]: prints the answer read from the terminal.
ask() {
  have_tty || return 1
  if [ "$UI" = 1 ]; then
    gum input --no-show-help --header "$1" --value "${2:-}" --char-limit 0 --width 78 </dev/tty
    return $?
  fi
  if [ -n "${2:-}" ]; then
    printf '%s [%s]: ' "$1" "$2" >/dev/tty
  else
    printf '%s: ' "$1" >/dev/tty
  fi
  IFS= read -r ask_answer </dev/tty || return 1
  printf '%s\n' "${ask_answer:-${2:-}}"
}

confirm() {
  [ "$ASSUME_YES" = 1 ] && return 0
  if [ "$UI" = 1 ]; then
    gum confirm --no-show-help --affirmative "Да" --negative "Нет" "$1" </dev/tty
    return $?
  fi
  confirm_answer="$(ask "$1 [y/N]" "")" || return 1
  case "$confirm_answer" in
    y | Y | yes | д | Д | да | Да) return 0 ;;
    *) return 1 ;;
  esac
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)
        REPO="${2:?--repo: нужен адрес}"
        shift 2
        ;;
      --space)
        SPACE="${2:?--space: нужен адрес}"
        shift 2
        ;;
      --name)
        NAME="${2:?--name: нужно имя}"
        shift 2
        ;;
      --dir)
        DIR="${2:?--dir: нужна папка}"
        shift 2
        ;;
      --bin-dir)
        BIN_DIR="${2:?--bin-dir: нужна папка}"
        shift 2
        ;;
      --template)
        TEMPLATE="${2:?--template: нужен адрес}"
        shift 2
        ;;
      --local)
        LOCAL=1
        shift
        ;;
      --project)
        PROJECT="${2:?--project: нужна папка}"
        shift 2
        ;;
      --no-launch)
        NO_LAUNCH=1
        shift
        ;;
      --core-only)
        CORE_ONLY=1
        NO_LAUNCH=1
        shift
        ;;
      --yes | -y)
        ASSUME_YES=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "неизвестный параметр: $1 (см. --help)" ;;
    esac
  done
}

check_environment() {
  if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1 &&
    { command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; } &&
    command -v tar >/dev/null 2>&1; then return 0; fi
  say "подготавливаю компоненты установки"
  case "$(uname -s)" in
    Darwin)
      xcode-select --install >/dev/null 2>&1 || true
      say "Ожидаю установки системных компонентов macOS. Подтвердите системный диалог, если он появился."
      bootstrap_attempt=0
      while ! git --version >/dev/null 2>&1; do
        bootstrap_attempt=$((bootstrap_attempt + 1))
        [ "$bootstrap_attempt" -lt 120 ] || die "системная установка Git не завершилась"
        sleep 5
      done
      ;;
    Linux)
      bootstrap_sudo=""
      if [ "$(id -u)" != 0 ]; then
        command -v sudo >/dev/null 2>&1 || die "для подготовки Git недоступны права установки"
        bootstrap_sudo=sudo
      fi
      if command -v apt-get >/dev/null 2>&1; then
        $bootstrap_sudo apt-get update -qq
        $bootstrap_sudo apt-get install -y -qq git curl ca-certificates tar
      elif command -v dnf >/dev/null 2>&1; then
        $bootstrap_sudo dnf install -y git curl tar
      elif command -v apk >/dev/null 2>&1; then
        $bootstrap_sudo apk add git curl tar ca-certificates
      elif command -v pacman >/dev/null 2>&1; then
        $bootstrap_sudo pacman -Sy --noconfirm git curl tar
      elif command -v zypper >/dev/null 2>&1; then
        $bootstrap_sudo zypper --non-interactive install git curl tar
      else die "для этой системы пока нет автоматического способа подготовки Git"; fi
      ;;
    *) die "для первого запуска в Windows используйте загрузчик install.ps1" ;;
  esac
  git --version >/dev/null 2>&1 || die "Git не запустился после установки"
}

prepare_tools() {
  STAGING="$(mktemp -d "${TMPDIR:-/tmp}/workbench-install.XXXXXX")"
  git clone -q "$TEMPLATE" "$STAGING/source"
  WB_DIR="$STAGING/source"
  # The helpers come from the same template snapshot as the installer.
  . "$WB_DIR/scripts/paths.sh"
  . "$WB_DIR/scripts/install-tools.sh"
  wb_install_tool jq || die "не удалось подготовить обработку настроек"
  if [ "$CORE_ONLY" != 1 ] && interactive; then
    wb_install_tool gum || die "не удалось подготовить мастер установки"
    UI=1
    gum style --foreground 33 --bold 'Установка workbench' >/dev/tty
    printf 'Enter - продолжить. Esc или Ctrl+C - отменить.\n' >/dev/tty
  fi
}

# absolute <path>: the path made absolute, with a leading ~ expanded. An answer read
# from the terminal holds a literal ~, which the shell never expanded.
absolute() {
  # shellcheck disable=SC2088
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#"~/"}" ;;
    [A-Za-z]:* | \\*)
      if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s\n' "$1"; fi
      ;;
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

# Sets DIR: from --dir, from the answer in the terminal, or ./<name>.
resolve_dir() {
  if [ -z "$DIR" ]; then
    existing_location=""
    if [ "$CORE_ONLY" != 1 ]; then
      # Existing user bindings also work before PATH has been prepared.
      for binding in "$(wb_codex_agents_md)" "$(wb_user_claude_md)"; do
        [ -f "$binding" ] || continue
        candidate_location="$(awk '
          /^<!-- workbench:user begin/ {owned=1; next}
          /^<!-- workbench:user end/ {owned=0}
          owned && /^- \$WORKBENCH = / {
            sub(/\r$/, "")
            sub(/^- \$WORKBENCH = /, "")
            sub(/ \(личная база этой машины\)$/, "")
            print; exit
          }
        ' "$binding")"
        [ -n "$candidate_location" ] || continue
        candidate_location="$(absolute "$candidate_location")"
        if [ -f "$candidate_location/scripts/setup.sh" ] && [ -f "$candidate_location/memory/MEMORY.md" ]; then
          existing_location=$candidate_location
          break
        fi
      done
    fi
    if [ "$CORE_ONLY" != 1 ] && [ -z "$existing_location" ] && command -v workbench >/dev/null 2>&1; then
      existing_location="$(workbench location 2>/dev/null || true)"
      if [ -z "$existing_location" ]; then
        existing_location="$(workbench help 2>/dev/null | sed -n '1s/^workbench - личная база этой машины: //p' || true)"
      fi
    fi
    if [ -n "$existing_location" ]; then
      existing_location="$(absolute "$existing_location")"
      if [ -f "$existing_location/scripts/setup.sh" ] && [ -f "$existing_location/memory/MEMORY.md" ]; then
        DIR=$existing_location
        say "найден ваш workbench: $(wb_native_path "$DIR")"
      fi
    fi
    if [ -z "$DIR" ]; then
      DIR="$HOME/$NAME"
      if interactive; then DIR="$(ask "Каталог workbench" "$(wb_native_path "$DIR")")"; fi
    fi
  fi
  DIR="$(absolute "$DIR")"
  BIN_DIR="$(absolute "$BIN_DIR")"
}

# Sets REPO from --repo, from --space and --name, or from answers in the terminal.
resolve_repo() {
  [ "$LOCAL" != 1 ] || return 0
  [ -n "$REPO" ] && return 0
  if [ "$UI" = 1 ] && [ -z "$SPACE" ]; then
    base_mode="$(gum choose --no-show-help --header "Ваш workbench" --label-delimiter ':' \
      'Создать workbench впервые:local' 'Скачать свой workbench из Git:remote' </dev/tty)" || exit 130
    if [ "$base_mode" = local ]; then
      LOCAL=1
      return 0
    fi
    REPO="$(ask "Адрес вашего частного Git-хранилища" "")" || exit 130
    [ -n "$REPO" ] || die "адрес хранилища не указан"
    return 0
  fi
  if [ "$ASSUME_YES" = 1 ] && [ -z "$SPACE" ]; then
    LOCAL=1
    return 0
  fi
  if [ -z "$SPACE" ] && interactive; then
    REPO="$(ask "Адрес закрытого хранилища для личной базы (пусто - собрать из пространства и имени)" "")"
    [ -n "$REPO" ] && return 0
    SPACE="$(ask "Пространство, например git@gitlab.com:you или https://gitlab.com/you" "")"
    NAME="$(ask "Имя хранилища" "$NAME")"
  fi
  [ -n "$SPACE" ] || die "не задано закрытое хранилище: --repo URL или --space URL [--name NAME] (см. --help)"
  REPO="${SPACE%/}/${NAME%.git}.git"
}

# An existing base is updated; a folder with something else is left alone.
existing_base() {
  [ -e "$DIR" ] || return 1
  if [ -f "$DIR/scripts/setup.sh" ] && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
    return 0
  fi
  [ -z "$(ls -A "$DIR" 2>/dev/null)" ] || die "в $DIR уже что-то есть, и это не личная база workbench"
  return 1
}

update_base() {
  # Updating the program does not synchronize personal work with another machine.
  say "использую вашу базу в $DIR"
}

# Creates the private repository from the template. The template stays a remote, so
# its program updates are imported by: workbench update
create_from_template() {
  say "создаю личную базу из шаблона $TEMPLATE"
  git clone -q --origin template "$TEMPLATE" "$DIR"
  git -C "$DIR" remote add origin "$REPO"
  if ! git -C "$DIR" push -u origin HEAD; then
    die "не удалось отправить в $REPO. Создай там пустое закрытое хранилище и выполни:
  git -C $DIR push -u origin HEAD && sh $DIR/scripts/setup.sh"
  fi
}

# A remote whose HEAD names a missing branch (e.g. a bare repository with default
# "master" that received "main") is cloned without a checkout: pick main or the
# first branch.
ensure_checkout() {
  git -C "$DIR" rev-parse --verify -q HEAD >/dev/null && return 0
  branches="$(git -C "$DIR" for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin | grep -vx HEAD || true)"
  branch="$(printf '%s\n' "$branches" | grep -x main || printf '%s\n' "$branches" | head -n 1)"
  [ -n "$branch" ] || die "в $REPO нет веток"
  git -C "$DIR" checkout -q -B "$branch" "origin/$branch"
}

make_base() {
  mkdir -p "$(dirname "$DIR")"
  if [ "$LOCAL" = 1 ]; then
    git clone -q --origin template "$TEMPLATE" "$DIR"
    # Personal data must never use the public template as the default push target.
    git -C "$DIR" branch --unset-upstream >/dev/null 2>&1 || true
    return 0
  fi
  rc=0
  git ls-remote --exit-code --heads "$REPO" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0)
      say "клонирую личную базу $REPO"
      git clone -q "$REPO" "$DIR"
      ensure_checkout
      git -C "$DIR" remote get-url template >/dev/null 2>&1 || git -C "$DIR" remote add template "$TEMPLATE"
      ;;
    2)
      say "хранилище $REPO пустое"
      create_from_template
      ;;
    *)
      confirm "Хранилище $REPO не найдено или нет доступа. Создать его из шаблона? (GitLab создаёт закрытый проект при первой отправке, на GitHub создай пустое закрытое хранилище заранее)" ||
        die "установка остановлена: проверь адрес и доступ к $REPO"
      create_from_template
      ;;
  esac
}

# The command is a small launcher: the code lives in the base and updates with it.
install_command() {
  mkdir -p "$BIN_DIR"
  quoted="$(printf '%s' "$DIR/bin/workbench" | sed "s/'/'\\\\''/g")"
  printf '#!/bin/sh\n# workbench command, made by install.sh: runs the personal base of this machine.\nexec sh '\''%s'\'' "$@"\n' "$quoted" >"$BIN_DIR/workbench"
  chmod +x "$BIN_DIR/workbench"
  if wb_windows; then
    command_target="$(cygpath -w "$DIR/bin/workbench.cmd" | sed 's/%/%%/g')"
    printf '@echo off\r\ncall "%s" %%*\r\nexit /b %%errorlevel%%\r\n' "$command_target" >"$BIN_DIR/workbench.cmd"
  fi
}

resolve_project() {
  [ -z "$PROJECT" ] || {
    PROJECT="$(absolute "$PROJECT")"
    return 0
  }
  [ "$CORE_ONLY" != 1 ] || return 0
  candidate="$(git -C "$INSTALL_CWD" rev-parse --show-toplevel 2>/dev/null || true)"
  # Never connect a base to itself or replace a workbench source checkout's bindings.
  if [ -n "$candidate" ] && [ -f "$candidate/scripts/setup.sh" ]; then candidate=""; fi
  if [ -z "$candidate" ] && [ -f "$DIR/.runtime/install.json" ]; then
    candidate="$(jq -r '.project // empty' "$DIR/.runtime/install.json")"
    [ -z "$candidate" ] || candidate="$(absolute "$candidate")"
    if [ -n "$candidate" ] && ! git -C "$candidate" rev-parse --git-dir >/dev/null 2>&1; then candidate=""; fi
  fi
  [ -n "$candidate" ] || return 0
  if [ "$UI" = 1 ]; then
    confirm "Подключить текущий проект $candidate?" || return 0
  fi
  PROJECT=$candidate
}

onboard() {
  WB_DIR=$DIR
  . "$WB_DIR/scripts/paths.sh"
  . "$WB_DIR/scripts/runtime.sh"
  wb_runtime_install "$BIN_DIR"
  wb_runtime_persist
  sh "$WB_DIR/scripts/attach.sh" --user
  [ -z "$PROJECT" ] || sh "$WB_DIR/scripts/attach.sh" "$PROJECT"
  if command -v codex >/dev/null 2>&1; then
    if confirm "Подключить хуки Codex: контекст, напоминания и защиту команд?"; then
      . "$WB_DIR/scripts/codex-rpc.sh"
      if [ -n "$PROJECT" ]; then
        wb_codex_trust "$WB_DIR" "$PROJECT" || die "Codex не подтвердил подключение хуков"
      else
        wb_codex_trust "$WB_DIR" || die "Codex не подтвердил подключение хуков"
      fi
    fi
  fi
  jq -n --arg base "$DIR" --arg bin "$BIN_DIR" --arg project "$PROJECT" --arg home "$HOME" \
    '{base: $base, binDir: $bin, project: $project, home: $home}' >"$DIR/.runtime/install.json"
  if [ -n "$PROJECT" ]; then
    sh "$DIR/scripts/doctor.sh" --project "$PROJECT" --report "$DIR/.runtime/doctor.json"
  else sh "$DIR/scripts/doctor.sh" --report "$DIR/.runtime/doctor.json"; fi
}

main() {
  parse_args "$@"
  check_environment
  prepare_tools
  resolve_dir
  resolve_project
  if existing_base; then
    if [ "$UI" = 1 ]; then
      confirm "Использовать существующий workbench и обновить подключения?" || exit 130
    fi
    update_base
  else
    resolve_repo
    if [ "$UI" = 1 ]; then
      project_display="сама папка workbench"
      [ -z "$PROJECT" ] || project_display="$(wb_native_path "$PROJECT")"
      gum style --bold "Ваш workbench: $(wb_native_path "$DIR")" "Подключаемый проект: $project_display" >/dev/tty
      confirm "Установить и настроить workbench?" || exit 130
    fi
    make_base
  fi
  WB_DIR=$DIR
  # shellcheck source=/dev/null
  . "$STAGING/source/scripts/upgrade.sh"
  wb_upgrade_program "$STAGING/source" || die "программа не обновлена; ваши файлы сохранены"
  sh "$DIR/scripts/setup.sh"
  install_command
  if [ "$CORE_ONLY" != 1 ]; then onboard; fi
  say "готово. Ваш workbench: $(wb_native_path "$DIR")"
  say "Диагностика в любой папке: workbench doctor"
  # A child installer cannot change its parent's environment. Enter a prepared shell
  # automatically; the persistent profile/registry also prepares future terminals.
  if [ "$CORE_ONLY" != 1 ] && [ "$NO_LAUNCH" != 1 ] && have_tty; then
    say "открываю готовую оболочку"
    exec "${SHELL:-sh}" -i </dev/tty >/dev/tty 2>&1
  fi
}

# Everything runs only after the whole script has been downloaded.
main "$@"
