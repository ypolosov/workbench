#!/usr/bin/env bash
# workbench installer. Run it in the root of a target project:
#
#   curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | bash -s -- \
#     --repo git@gitlab.com:you/my-workbench.git
#
# It puts the owner's private knowledge-base repository into ./.workbench (creating
# it from the public template when that repository is empty or missing), prepares the
# pinned FPF edition and connects the workbench to the project without touching the
# project's history. Re-running it in the same project updates the workbench.
set -euo pipefail

TEMPLATE="${WORKBENCH_TEMPLATE:-https://github.com/ypolosov/workbench.git}"
REPO="${WORKBENCH_REPO:-}"
BASE="${WORKBENCH_BASE:-}"
NAME="${WORKBENCH_NAME:-my-workbench}"
ASSUME_YES="${WORKBENCH_YES:-0}"
DEST=".workbench"

usage() {
  cat <<'EOF'
Установка workbench в текущий проект (запускать в корне git-проекта).

  curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/ypolosov/workbench/main/install.sh | bash -s -- \
    --repo git@gitlab.com:you/my-workbench.git

Параметры (в скобках - переменные окружения):
  --repo URL      адрес закрытого хранилища с личной базой             [WORKBENCH_REPO]
  --base URL      пространство для нового хранилища,                    [WORKBENCH_BASE]
                  например git@gitlab.com:you или https://gitlab.com/you
  --name NAME     имя хранилища вместе с --base, по умолчанию my-workbench [WORKBENCH_NAME]
  --template URL  публичный шаблон, по умолчанию                        [WORKBENCH_TEMPLATE]
                  https://github.com/ypolosov/workbench.git
  --yes           ничего не спрашивать; создать хранилище, если его нет [WORKBENCH_YES=1]
  -h, --help      эта справка

Без --repo и --base установщик спрашивает адрес в терминале.
EOF
}

say() {
  printf 'workbench: %s\n' "$*" >&2
}

die() {
  say "$*"
  exit 1
}

# Answers come from the terminal: under curl | bash, stdin is the script itself.
have_tty() {
  (: </dev/tty) 2>/dev/null
}

ask() {
  local prompt="$1" default="${2:-}" answer
  have_tty || return 1
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$prompt" "$default" >/dev/tty
  else
    printf '%s: ' "$prompt" >/dev/tty
  fi
  IFS= read -r answer </dev/tty || return 1
  printf '%s\n' "${answer:-$default}"
}

confirm() {
  local answer
  [ "$ASSUME_YES" = 1 ] && return 0
  answer="$(ask "$1 [y/N]" "")" || return 1
  case "$answer" in
    y | Y | yes | д | Д | да | Да) return 0 ;;
    *) return 1 ;;
  esac
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) REPO="${2:?--repo: нужен адрес}"; shift 2 ;;
      --base) BASE="${2:?--base: нужен адрес}"; shift 2 ;;
      --name) NAME="${2:?--name: нужно имя}"; shift 2 ;;
      --template) TEMPLATE="${2:?--template: нужен адрес}"; shift 2 ;;
      --yes | -y) ASSUME_YES=1; shift ;;
      -h | --help) usage; exit 0 ;;
      *) die "неизвестный параметр: $1 (см. --help)" ;;
    esac
  done
}

check_environment() {
  local top
  command -v git >/dev/null || die "нужен git"
  command -v jq >/dev/null || die "нужен jq: https://jqlang.org"
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "запусти установщик в корне git-проекта"
  [ "$(cd "$top" && pwd -P)" = "$(pwd -P)" ] || die "запусти установщик в корне проекта: $top"
}

# Sets REPO from --repo, from --base and --name, or from answers in the terminal.
resolve_repo() {
  [ -n "$REPO" ] && return 0
  if [ -z "$BASE" ] && [ "$ASSUME_YES" != 1 ] && have_tty; then
    REPO="$(ask "Адрес закрытого хранилища для личной базы (пусто - собрать из пространства и имени)" "")"
    [ -n "$REPO" ] && return 0
    BASE="$(ask "Пространство, например git@gitlab.com:you или https://gitlab.com/you" "")"
    NAME="$(ask "Имя хранилища" "$NAME")"
  fi
  [ -n "$BASE" ] || die "не задано закрытое хранилище: --repo URL или --base URL [--name NAME] (см. --help)"
  REPO="${BASE%/}/${NAME%.git}.git"
}

# Creates the private repository from the template. The template stays a remote, so
# its updates merge with: git -C .workbench pull template main
bootstrap() {
  say "создаю личную базу из шаблона $TEMPLATE"
  git clone -q --origin template "$TEMPLATE" "$DEST"
  git -C "$DEST" remote add origin "$REPO"
  if ! git -C "$DEST" push -u origin HEAD; then
    die "не удалось отправить в $REPO. Создай там пустое закрытое хранилище и выполни:
  git -C $DEST push -u origin HEAD && bash $DEST/scripts/setup.sh"
  fi
}

# Keeps .workbench out of the project's git from the start, even if setup fails later.
exclude_dest() {
  local exclude
  exclude="$(git rev-parse --absolute-git-dir)/info/exclude"
  mkdir -p "$(dirname "$exclude")"
  if ! grep -qxF "/$DEST/" "$exclude" 2>/dev/null; then
    printf '# workbench clone: personal, never commit\n/%s/\n' "$DEST" >>"$exclude"
  fi
}

# A remote whose HEAD names a missing branch (e.g. a bare repository with default
# "master" that received "main") is cloned without a checkout: pick main or the
# first branch.
ensure_checkout() {
  local branches branch
  git -C "$DEST" rev-parse --verify -q HEAD >/dev/null && return 0
  branches="$(git -C "$DEST" for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin | grep -vx HEAD || true)"
  branch="$(printf '%s\n' "$branches" | grep -x main || printf '%s\n' "$branches" | head -1)"
  [ -n "$branch" ] || die "в $REPO нет веток"
  git -C "$DEST" checkout -q -B "$branch" "origin/$branch"
}

install_clone() {
  local rc=0
  git ls-remote --exit-code --heads "$REPO" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0)
      say "клонирую личную базу $REPO"
      git clone -q "$REPO" "$DEST"
      ensure_checkout
      git -C "$DEST" remote get-url template >/dev/null 2>&1 || git -C "$DEST" remote add template "$TEMPLATE"
      ;;
    2)
      say "хранилище $REPO пустое"
      bootstrap
      ;;
    *)
      confirm "Хранилище $REPO не найдено или нет доступа. Создать его из шаблона? (GitLab создаёт закрытый проект при первой отправке, на GitHub создай пустое закрытое хранилище заранее)" ||
        die "установка остановлена: проверь адрес и доступ к $REPO"
      bootstrap
      ;;
  esac
}

main() {
  parse_args "$@"
  check_environment
  if [ -e "$DEST" ]; then
    say "$DEST уже есть: обновляю"
    git -C "$DEST" pull --ff-only || die "не удалось обновить $DEST, разберись вручную"
  else
    resolve_repo
    exclude_dest
    install_clone
  fi
  bash "$DEST/scripts/setup.sh"
  cat >&2 <<EOF

workbench: готово.
  Личная база: $DEST ($(git -C "$DEST" remote get-url origin)), git проекта её не видит.
  Маркеры компании для проверки перед сохранением: $(git -C "$DEST" rev-parse --absolute-git-dir)/info/company-markers
  Работать: claude в корне проекта. Обновить шаблон: git -C $DEST pull template main
EOF
}

# Everything runs only after the whole script has been downloaded.
main "$@"
