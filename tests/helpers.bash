# shellcheck shell=bash
# Helpers for the workbench tests (bats). Every test file builds its own offline
# sandbox with make_sandbox: a local bare repository stands in for the owner's private
# repository, a tiny local repository stands in for FPF, and the template is a snapshot
# of this working tree, uncommitted changes included. The owner's projects,
# repositories and git settings are never touched.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"

# --- sandbox ----------------------------------------------------------------------

# make_sandbox: exports SANDBOX, FPF_SRC, FPF_OLD, FPF_PINNED, FPF_NEWER, TPL, PRIVATE,
# the git settings and the home folder of the sandbox. Call it from setup_file.
make_sandbox() {
  # Keep the caller's context out: variables of a surrounding git hook (GIT_DIR and
  # friends) and installer settings.
  # shellcheck disable=SC2046
  unset $(git rev-parse --local-env-vars) \
    WORKBENCH_TEMPLATE WORKBENCH_REPO WORKBENCH_BASE WORKBENCH_NAME WORKBENCH_YES \
    CLAUDE_CONFIG_DIR
  SANDBOX="$(cd "$BATS_FILE_TMPDIR" && pwd -P)"
  export SANDBOX HOME="$SANDBOX/home"
  mkdir -p "$HOME"
  export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig" GIT_CONFIG_NOSYSTEM=1
  git config --global user.name "workbench test"
  git config --global user.email "test@example.invalid"
  git config --global init.defaultBranch main
  make_fpf
  make_template
  export PRIVATE="$SANDBOX/private.git"
  git init -q --bare "$PRIVATE"
}

# A tiny FPF stand-in with three editions; the middle one is pinned.
make_fpf() {
  export FPF_SRC="$SANDBOX/fpf" FPF_OLD FPF_PINNED FPF_NEWER
  git init -q "$FPF_SRC"
  printf '# Using FPF (test stand-in)\n' >"$FPF_SRC/USING-FPF.md"
  FPF_OLD="$(fpf_edition old)"
  FPF_PINNED="$(fpf_edition pinned)"
  FPF_NEWER="$(fpf_edition newer)"
}

fpf_edition() {
  printf '## A.1 %s edition\n### A.1:End\n' "$1" >"$FPF_SRC/FPF-Spec.md" &&
    git -C "$FPF_SRC" add FPF-Spec.md USING-FPF.md &&
    git -C "$FPF_SRC" commit -qm "$1 edition" &&
    git -C "$FPF_SRC" rev-parse HEAD
}

# The template: this working tree with its uncommitted changes, FPF pointed at the stand-in.
make_template() {
  local list="$SANDBOX/template.files"
  export TPL="$SANDBOX/template"
  mkdir "$TPL"
  git -C "$ROOT" ls-files -z --cached --others --exclude-standard |
    while IFS= read -r -d '' f; do
      if [ -e "$ROOT/$f" ] || [ -L "$ROOT/$f" ]; then printf '%s\n' "$f"; fi
    done >"$list"
  tar -C "$ROOT" -cf - -T "$list" | tar -C "$TPL" -xf -
  printf 'url=file://%s\ncommit=%s\n' "$FPF_SRC" "$FPF_PINNED" >"$TPL/.fpf-edition"
  git init -q "$TPL"
  git -C "$TPL" add --pathspec-from-file="$list"
  git -C "$TPL" commit -qm "template snapshot"
}

# new_project <dir>: a git project with one commit that ignores local Claude settings.
new_project() {
  git init -q "$1"
  printf '# %s\n' "$(basename "$1")" >"$1/README.md"
  printf '.claude/settings.local.json\n' >"$1/.gitignore"
  git -C "$1" add README.md .gitignore
  git -C "$1" commit -qm "project start"
  mkdir -p "$1/.git/info"
  touch "$1/.git/info/exclude"
}

# --- actions ----------------------------------------------------------------------

# bootstrap <base dir> [args...]: runs install.sh the way `curl ... | sh -s -- args` does,
# with the workbench command installed into the sandbox.
bootstrap() {
  local dir="$1"
  shift
  (cd "$SANDBOX" && sh -s -- --template "$TPL" --dir "$dir" --bin-dir "$SANDBOX/bin" "$@" <"$TPL/install.sh")
}

# wb <dir> <command...>: the installed workbench command, run in the given folder.
wb() {
  local dir="$1"
  shift
  (cd "$dir" && "$SANDBOX/bin/workbench" "$@")
}

# hook <project> <script> <json>: runs a hook command from the project's generated
# settings the way Claude Code does: through a shell, in the project, with CLAUDE_PROJECT_DIR.
hook() {
  hook_from "$1/.claude/settings.local.json" "$@"
}

# hook_from <settings file> <project> <script> <json>: the same for any settings file.
hook_from() {
  local cmd
  # The script name goes in without a leading slash: Git Bash rewrites such arguments as paths.
  cmd="$(jq -r --arg s "$3" '[.. | objects | .command? | strings | select(contains("/" + $s))][0] // empty' "$1")"
  [ -n "$cmd" ] || return 90
  (cd "$2" && printf '%s' "$4" | CLAUDE_PROJECT_DIR="$2" sh -c "$cmd")
}

# on_windows: the tests run in Git Bash, MSYS2 or Cygwin on Windows.
on_windows() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) return 0 ;;
  esac
  return 1
}

# codex_hook <project> <script> <json> [<folder>]: runs a hook command from the project's
# Codex hooks the way Codex does, in the session folder (by default the project) and
# without CLAUDE_PROJECT_DIR: through sh, and on Windows its commandWindows through
# cmd.exe (a one-line batch file stands in for cmd.exe /C "<line>").
codex_hook() {
  local cmd key=command
  if on_windows; then key=commandWindows; fi
  cmd="$(jq -r --arg k "$key" --arg s "$2" '[.. | objects | .[$k]? | strings | select(contains("/" + $s))][0] // empty' "$1/.codex/hooks.json")"
  [ -n "$cmd" ] || return 90
  if on_windows; then
    printf '@%s\r\n' "$cmd" >"$BATS_TEST_TMPDIR/codex-hook.cmd"
    # //c: Git Bash passes it as /c; no MSYS variables, which would reach git in the hook.
    (cd "${4:-$1}" && unset CLAUDE_PROJECT_DIR && printf '%s' "$3" |
      cmd //c "$(cygpath -w "$BATS_TEST_TMPDIR/codex-hook.cmd")")
  else
    (cd "${4:-$1}" && unset CLAUDE_PROJECT_DIR && printf '%s' "$3" | sh -c "$cmd")
  fi
}

# cursor_hook <project> <script> <json>: runs a hook command from the project's Claude Code
# settings the way Cursor does: it reads them as third-party hooks and sets
# CURSOR_PROJECT_DIR next to CLAUDE_PROJECT_DIR.
cursor_hook() {
  local cmd
  cmd="$(jq -r --arg s "$2" '[.. | objects | .command? | strings | select(contains("/" + $s))][0] // empty' "$1/.claude/settings.local.json")"
  [ -n "$cmd" ] || return 90
  (cd "$1" && printf '%s' "$3" | CURSOR_PROJECT_DIR="$1" CLAUDE_PROJECT_DIR="$1" sh -c "$cmd")
}

cursor_session_input() {
  jq -n --arg root "$1" '{hook_event_name: "sessionStart", cursor_version: "3.10.20", workspace_roots: [$root]}'
}

# context_of <hook output>: the additionalContext the hook returned.
context_of() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

session_input() {
  jq -n --arg cwd "$1" '{hook_event_name: "SessionStart", source: "startup", cwd: $cwd}'
}

prompt_input() {
  jq -n --arg cwd "$1" --arg p "$2" '{hook_event_name: "UserPromptSubmit", prompt: $p, cwd: $cwd}'
}

bash_input() {
  jq -n --arg cwd "$1" --arg c "$2" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}, cwd: $cwd}'
}

# commit_note <clone> <text>: commits a line in the fleeting notes; a refused commit
# is rolled back.
commit_note() {
  printf '%s\n' "$2" >>"$1/inbox/fleeting-notes.md"
  git -C "$1" add -- inbox/fleeting-notes.md
  if git -C "$1" commit -qm "test: note"; then
    return 0
  fi
  git -C "$1" restore --staged --worktree -- inbox/fleeting-notes.md
  return 1
}

# --- predicates -------------------------------------------------------------------

# same_dir <a> <b>: both paths name the same folder; Git for Windows prints C:/ paths.
same_dir() {
  [ "$(cd "$1" 2>/dev/null && pwd -P)" = "$(cd "$2" 2>/dev/null && pwd -P)" ]
}

remotes_ok() {
  same_dir "$(git -C "$1" remote get-url origin)" "$PRIVATE" &&
    same_dir "$(git -C "$1" remote get-url template)" "$TPL"
}

# worktree_listed <repo> <dir>: git's record of the repository's worktrees names the folder.
worktree_listed() {
  local wt
  while IFS= read -r wt; do
    same_dir "$wt" "$2" && return 0
  done < <(git -C "$1" worktree list --porcelain | sed -n 's/^worktree //p')
  return 1
}

# Only the pinned FPF edition is in the clone: neither its history nor later editions.
only_pinned_fetched() {
  git -C "$1" cat-file -e "$FPF_PINNED^{commit}" &&
    ! git -C "$1" cat-file -e "$FPF_OLD^{commit}" 2>/dev/null &&
    ! git -C "$1" cat-file -e "$FPF_NEWER^{commit}" 2>/dev/null
}

skills_linked() {
  local skill
  for skill in "$1"/.workbench/.agents/skills/*/; do
    [ -f "$1/.claude/skills/$(basename "$skill")/SKILL.md" ] || return 1
  done
}

# project_files <dir>: the project's files outside .git and .workbench.
project_files() {
  (cd "$1" && find . -path ./.git -prune -o -path ./.workbench -prune -o -print) | LC_ALL=C sort
}

# The exclude file is the original one plus the two lines that keep the clone out.
exclude_restored() {
  { grep -vxF -e '# workbench clone: personal, never commit' -e '/.workbench/' "$1/.git/info/exclude" || true; } |
    cmp -s - "$2"
}

# session_context <project>: the context the session-start hook gives; fails when the hook fails.
session_context() {
  local out
  out="$(hook "$1" session-start.sh "$(session_input "$1")")" || return 1
  context_of "$out"
}

# prompt_context <project> <script> <prompt>: the context a prompt hook gives.
prompt_context() {
  local out
  out="$(hook "$1" "$2" "$(prompt_input "$1" "$3")")" || return 1
  context_of "$out"
}
