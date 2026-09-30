#!/bin/sh
# workbench installer (bootstrap): makes the personal base of this machine and installs
# the workbench command. Run it anywhere:
#
#   curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh
#
# The base is the only local clone of the owner's private repository on this machine;
# when that repository is empty or missing, it is created from the public template.
# Running the installer again for the same folder updates the base. Projects are
# connected afterwards, one by one: `workbench attach` in the project's folder.
set -eu

TEMPLATE="${WORKBENCH_TEMPLATE:-https://github.com/ypolosov/workbench.git}"
REPO="${WORKBENCH_REPO:-}"
SPACE="${WORKBENCH_SPACE:-}"
NAME="${WORKBENCH_NAME:-my-workbench}"
DIR="${WORKBENCH_DIR:-}"
BIN_DIR="${WORKBENCH_BIN_DIR:-$HOME/.local/bin}"
ASSUME_YES="${WORKBENCH_YES:-0}"

usage() {
  cat <<'EOF'
Установка личной базы workbench на эту машину.

  curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | sh -s -- \
    --repo git@gitlab.com:you/my-workbench.git --dir ~/my-workbench

Параметры (в скобках - переменные окружения):
  --repo URL      закрытое хранилище личной базы                          [WORKBENCH_REPO]
  --space URL     пространство для нового хранилища,                       [WORKBENCH_SPACE]
                  например git@gitlab.com:you или https://gitlab.com/you
  --name NAME     имя хранилища вместе с --space, по умолчанию my-workbench [WORKBENCH_NAME]
  --dir PATH      папка базы на этой машине, по умолчанию ./<имя>           [WORKBENCH_DIR]
  --bin-dir PATH  куда поставить команду workbench, по умолчанию ~/.local/bin [WORKBENCH_BIN_DIR]
  --template URL  публичный шаблон, по умолчанию                           [WORKBENCH_TEMPLATE]
                  https://github.com/ypolosov/workbench.git
  --yes           ничего не спрашивать; создать хранилище, если его нет    [WORKBENCH_YES=1]
  -h, --help      эта справка

Без параметров установщик спрашивает всё в терминале. Если папка базы уже есть,
установщик обновляет базу и заново ставит команду workbench.
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
  command -v git >/dev/null || die "нужен git"
  command -v jq >/dev/null || die "нужен jq: https://jqlang.org"
}

# absolute <path>: the path made absolute, with a leading ~ expanded. An answer read
# from the terminal holds a literal ~, which the shell never expanded.
absolute() {
  # shellcheck disable=SC2088
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${1#"~/"}" ;;
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

# Sets DIR: from --dir, from the answer in the terminal, or ./<name>.
resolve_dir() {
  if [ -z "$DIR" ]; then
    DIR="$PWD/$NAME"
    if interactive; then DIR="$(ask "Папка личной базы на этой машине" "$DIR")"; fi
  fi
  DIR="$(absolute "$DIR")"
  BIN_DIR="$(absolute "$BIN_DIR")"
}

# Sets REPO from --repo, from --space and --name, or from answers in the terminal.
resolve_repo() {
  [ -n "$REPO" ] && return 0
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
  say "база уже есть в $DIR: обновляю"
  if git -C "$DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    git -C "$DIR" pull -q --ff-only || die "не удалось обновить $DIR, разберись вручную"
  fi
}

# Creates the private repository from the template. The template stays a remote, so
# its updates merge with: git pull template main
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
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) say "папки $BIN_DIR нет в PATH: добавь в профиль оболочки строку  export PATH=\"$BIN_DIR:\$PATH\"" ;;
  esac
}

main() {
  parse_args "$@"
  check_environment
  resolve_dir
  if existing_base; then
    update_base
  else
    resolve_repo
    make_base
  fi
  sh "$DIR/scripts/setup.sh"
  install_command
  cat >&2 <<EOF

workbench: готово.
  Личная база: $DIR ($(git -C "$DIR" remote get-url origin))
  Команда: $BIN_DIR/workbench
  Подключить к проекту: в папке проекта  workbench attach
  Маркеры компании для проверки перед сохранением: $(git -C "$DIR" rev-parse --absolute-git-dir)/info/company-markers
  Обновления шаблона: git -C $DIR pull template main
EOF
}

# Everything runs only after the whole script has been downloaded.
main "$@"
