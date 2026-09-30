#!/bin/sh
# Guard against irreversible shell commands, the same for every agent: the command text
# comes on stdin, as the agent's hook adapter took it from the hook input. Exit 2 with the
# reason on stderr refuses the command; exit 0 lets it through. Empty text is refused too.
# Refused: staging everything (git add -A/--all/-u/.), rewriting or deleting remote
# history (git push --force/-f/+ref/--mirror/--delete/-d/:ref), git reset --hard,
# git clean -f without a dry run, rm -r -f outside temporary directories, gh repo
# delete, and a top-level cd (Claude Code keeps the working directory between calls).
# Quoted text, comments and heredoc bodies are data, unless a shell reads the heredoc.
# The rules follow the destructive-guard hook of FMT-exocortex-template (MIT, Tseren
# Tserenov); this is a shorter rewrite in POSIX sh and awk.
set -u

block() {
  echo "BLOCKED: $1" >&2
  exit 2
}

# Drops heredoc bodies that no shell reads. With an unterminated heredoc the text stays
# as it is, so a false match hides nothing.
# An awk program, not shell text.
# shellcheck disable=SC2016
STRIP_HEREDOCS='
function shell_reads(line, n, i, w, words) {
  n = split(line, words, /[ \t;&|()`]+/)
  for (i = 1; i <= n; i++) {
    w = words[i]
    sub(/^.*\//, "", w)
    if (w ~ /^(sh|bash|dash|zsh|ksh|ssh)$/) return 1
  }
  return 0
}
{
  all = all $0 "\n"
  if (open > 0) {
    probe = $0
    if (tabs[body]) sub(/^\t+/, "", probe)
    if (probe == word[body]) {
      if (++body > open) open = 0
    } else if (keep) out = out $0 "\n"
    next
  }
  out = out $0 "\n"
  scan = $0
  gsub(/<<</, "\001\001\001", scan)
  body = 1
  keep = shell_reads($0)
  while (match(scan, /<<-?[ \t]*(["\047][A-Za-z_][A-Za-z0-9_]*["\047]|[A-Za-z_][A-Za-z0-9_]*)/)) {
    op = substr(scan, RSTART, RLENGTH)
    scan = substr(scan, RSTART + RLENGTH)
    w = op
    sub(/^<<-?[ \t]*/, "", w)
    gsub(/["\047]/, "", w)
    word[++open] = w
    tabs[open] = (substr(op, 3, 1) == "-")
  }
}
END { printf "%s", (open > 0 ? all : out) }
'

# Splits the command text into simple commands, one per line: nesting depth, then the
# words, all separated by \037. Quotes are resolved, comments dropped; ( $( and `
# open a nested level, where cd does not change the caller's directory.
# shellcheck disable=SC2016
SEGMENTS='
function flush_token() {
  if (has) seg = seg US tok
  tok = ""
  has = 0
}
function flush_segment() {
  flush_token()
  if (seg != "") print depth seg
  seg = ""
}
BEGIN { US = "\037"; depth = 0; tick = 0; has = 0; q = "" }
{ text = text $0 "\n" }
END {
  n = length(text)
  for (i = 1; i <= n; i++) {
    c = substr(text, i, 1)
    if (q == "\047") {
      if (c == "\047") q = ""
      else tok = tok c
      continue
    }
    if (q == "\"") {
      if (c == "\\" && substr(text, i + 1, 1) ~ /["\\$`]/) tok = tok substr(text, ++i, 1)
      else if (c == "\"") q = ""
      else tok = tok c
      continue
    }
    if (c == "\047" || c == "\"") {
      q = c
      has = 1
      continue
    }
    if (c == "\\") {
      if (substr(text, i + 1, 1) != "\n") {
        tok = tok substr(text, i + 1, 1)
        has = 1
      }
      i++
      continue
    }
    if (c == "#" && !has) {
      while (i < n && substr(text, i + 1, 1) != "\n") i++
      continue
    }
    if (c == " " || c == "\t") {
      flush_token()
      continue
    }
    if (index(";&|(){}`\n", c)) {
      flush_segment()
      if (c == "(") depth++
      else if (c == ")" && depth > 0) depth--
      else if (c == "`") {
        if (tick) { tick = 0; if (depth > 0) depth-- }
        else { tick = 1; depth++ }
      }
      continue
    }
    tok = tok c
    has = 1
  }
  flush_segment()
}
'

# temp_path <path>: the path lies inside a temporary directory, without ".." tricks.
# The command text names $TMPDIR literally when the agent writes it that way.
temp_path() {
  # shellcheck disable=SC2016
  case $1 in
    *..*) return 1 ;;
    /tmp/?* | /var/tmp/?* | /private/tmp/?* | '$TMPDIR/'?* | '${TMPDIR}/'?*) return 0 ;;
  esac
  case ${TMPDIR:-} in
    '' | /) return 1 ;;
  esac
  case $1 in
    "${TMPDIR%/}"/?*) return 0 ;;
  esac
  return 1
}

check_git_add() {
  for arg; do
    case $arg in
      -A | --all | -u | --update | . | ./ | :/) block "git add $arg запрещён: подхватывает чужие изменения. Добавляй конкретные файлы: git add <путь>." ;;
      --*) ;;
      -*[Au]*) block "git add $arg запрещён: подхватывает чужие изменения. Добавляй конкретные файлы: git add <путь>." ;;
    esac
  done
}

check_git_push() {
  for arg; do
    case $arg in
      --force | --force=*) block "git push --force запрещён: перезаписывает историю. Используй --force-with-lease или согласуй с владельцем." ;;
      --mirror | --delete) block "git push $arg запрещён: удаляет в удалённом хранилище. Согласуй с владельцем." ;;
      --*) ;;
      -*f*) block "git push $arg запрещён: перезаписывает историю. Используй --force-with-lease или согласуй с владельцем." ;;
      -*d*) block "git push $arg запрещён: удаляет в удалённом хранилище. Согласуй с владельцем." ;;
      +*) block "git push $arg запрещён: плюс перед веткой перезаписывает историю. Согласуй с владельцем." ;;
      :*) block "git push $arg запрещён: двоеточие перед веткой удаляет её в удалённом хранилище. Согласуй с владельцем." ;;
    esac
  done
}

check_git_reset() {
  for arg; do
    case $arg in
      --hard) block "git reset --hard запрещён: теряет несохранённые изменения. Используй git stash." ;;
    esac
  done
}

check_git_clean() {
  clean_force=0
  clean_dry=0
  for arg; do
    case $arg in
      --force) clean_force=1 ;;
      --dry-run) clean_dry=1 ;;
      --*) ;;
      -*)
        case $arg in *f*) clean_force=1 ;; esac
        case $arg in *n*) clean_dry=1 ;; esac
        ;;
    esac
  done
  if [ "$clean_force" = 1 ] && [ "$clean_dry" = 0 ]; then
    block "git clean -f запрещён: удаляет неотслеживаемые файлы. Согласуй с владельцем."
  fi
}

check_git() {
  while [ $# -gt 0 ]; do
    case $1 in
      -C | -c | --git-dir | --work-tree | --namespace | --config-env)
        shift
        if [ $# -gt 0 ]; then shift; fi
        ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  git_command=$1
  shift
  case $git_command in
    add) check_git_add "$@" ;;
    push) check_git_push "$@" ;;
    reset) check_git_reset "$@" ;;
    clean) check_git_clean "$@" ;;
  esac
}

check_rm() {
  rm_recursive=0
  rm_force=0
  rm_unsafe=0
  rm_options=1
  rm_skip=0
  for arg; do
    if [ "$rm_skip" = 1 ]; then
      rm_skip=0
      continue
    fi
    if [ "$rm_options" = 1 ]; then
      case $arg in
        --)
          rm_options=0
          continue
          ;;
        --recursive)
          rm_recursive=1
          continue
          ;;
        --force)
          rm_force=1
          continue
          ;;
        --*) continue ;;
        -?*)
          case $arg in *[rR]*) rm_recursive=1 ;; esac
          case $arg in *f*) rm_force=1 ;; esac
          continue
          ;;
      esac
    fi
    case $arg in
      '>' | '>>' | '<' | [0-9]'>' | [0-9]'>>' | [0-9]'<')
        rm_skip=1
        continue
        ;;
      '>'* | '<'* | [0-9]'>'* | [0-9]'<'*) continue ;;
    esac
    temp_path "$arg" || rm_unsafe=1
  done
  if [ "$rm_recursive" = 1 ] && [ "$rm_force" = 1 ]; then
    if [ "$via_xargs" = 1 ] || [ "$rm_unsafe" = 1 ]; then
      block "rm -r -f вне временных папок (/tmp, \$TMPDIR) запрещён: удаление необратимо. Согласуй с владельцем."
    fi
  fi
}

check_gh() {
  if [ "${1:-}" = repo ] && [ "${2:-}" = delete ]; then
    block "gh repo delete запрещён: удаление хранилища необратимо. Согласуй с владельцем."
  fi
}

# check_segment <depth> <word...>: one simple command. Assignments, shell keywords and
# wrappers such as sudo or xargs in front of the command are skipped.
check_segment() {
  [ $# -gt 1 ] || return 0
  depth=$1
  shift
  via_xargs=0
  while [ $# -gt 0 ]; do
    case $1 in
      [A-Za-z_]*=*) shift ;;
      if | then | else | elif | do | while | until | '!') shift ;;
      sudo | doas | command | builtin | exec | env | nohup | time | nice | setsid | stdbuf | timeout | xargs)
        wrapper=$1
        if [ "$wrapper" = xargs ]; then via_xargs=1; fi
        shift
        while [ $# -gt 0 ]; do
          case $1 in
            -*) shift ;;
            *) break ;;
          esac
        done
        # timeout takes a duration before the command.
        if [ "$wrapper" = timeout ] && [ $# -gt 0 ]; then shift; fi
        ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  name=${1##*/}
  shift
  case $name in
    cd)
      if [ "$depth" = 0 ]; then
        block "верхнеуровневый cd запрещён: используй git -C <путь>, абсолютный путь или (cd <путь> && ...)."
      fi
      ;;
    git) check_git "$@" ;;
    rm) check_rm "$@" ;;
    gh) check_gh "$@" ;;
  esac
}

cmd_text="$(cat)"
[ -n "$cmd_text" ] || block "команда пустая; блокирую как неопределённо опасный запрос."

code="$(printf '%s\n' "$cmd_text" | LC_ALL=C awk "$STRIP_HEREDOCS")"
segments="$(printf '%s\n' "$code" | LC_ALL=C awk "$SEGMENTS")"

US="$(printf '\037')"
set -f
while IFS= read -r segment; do
  IFS="$US"
  # Split on the separator; globbing is off.
  # shellcheck disable=SC2086
  set -- $segment
  unset IFS
  check_segment "$@"
done <<EOF
$segments
EOF
exit 0
