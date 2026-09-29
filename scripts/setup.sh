#!/bin/sh
# Initializes this workbench clone: pinned FPF worktree in .fpf, git hooks and
# local settings; then connects the host project when the clone lives in
# <project>/.workbench. Idempotent: safe to re-run.
set -eu

WB_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=paths.sh
. "$WB_DIR/scripts/paths.sh"

fpf_url="$(wb_fpf_edition url)"
fpf_commit="$(wb_fpf_edition commit)"

# 1. FPF is a second remote of this repository; the pinned edition is a locked worktree.
git -C "$WB_DIR" remote get-url fpf >/dev/null 2>&1 || git -C "$WB_DIR" remote add fpf "$fpf_url"
if ! git -C "$WB_DIR" cat-file -e "$fpf_commit^{commit}" 2>/dev/null; then
  # Only the pinned snapshot is needed: fetching that one commit is several times
  # smaller than the whole FPF history. Servers that refuse fetch-by-commit get a full fetch.
  if ! git -C "$WB_DIR" fetch -q --depth 1 --no-tags fpf "$fpf_commit"; then
    echo "note: fetching the full FPF history instead" >&2
    git -C "$WB_DIR" fetch -q --no-tags fpf
  fi
fi
if [ ! -e "$FPF_DIR/.git" ]; then
  git -C "$WB_DIR" worktree add -q --detach "$FPF_DIR" "$fpf_commit"
  git -C "$WB_DIR" worktree lock --reason "pinned FPF edition, see .fpf-edition" "$FPF_DIR"
fi
# After a move the repository's record of the worktree is stale: repair it, then keep
# the worktree's own link relative (as git writes for submodules) so the pair also
# works when the project is mounted elsewhere, e.g. in a devcontainer. Native
# relative worktree paths need git 2.48+.
git -C "$WB_DIR" worktree repair "$FPF_DIR" >/dev/null 2>&1 || echo "WARN: git worktree repair failed for .fpf" >&2
worktree_id="$(basename "$(git -C "$FPF_DIR" rev-parse --absolute-git-dir)")"
printf 'gitdir: ../.git/worktrees/%s\n' "$worktree_id" >"$FPF_DIR/.git"
current="$(git -C "$FPF_DIR" rev-parse HEAD)"
[ "$current" = "$fpf_commit" ] || echo "WARN: .fpf is at $current, pinned edition is $fpf_commit" >&2

# 2. Git hooks work for any agent and for a human.
git -C "$WB_DIR" config core.hooksPath .githooks
chmod +x "$WB_DIR"/adapters/claude/hooks/*.sh "$WB_DIR"/.githooks/* "$WB_DIR"/scripts/*.sh

# 3. Sessions opened in the workbench itself keep Claude Code auto-memory here and get
#    the personal overlay; a clone opened on its own also gets the adapter's hooks.
#    All of it is local: autoMemoryDirectory is ignored in a committed settings.json.
host="$(wb_host_project)" || host=""
mkdir -p "$WB_DIR/.claude"
local_settings="$WB_DIR/.claude/settings.local.json"
settings="$(jq -n --arg dir "$WB_DIR/memory" '{autoMemoryDirectory: $dir}')"
if [ -z "$host" ]; then
  # Expanded by the shell that runs each hook, not here.
  # shellcheck disable=SC2016
  hooks="$(wb_hooks_json '$CLAUDE_PROJECT_DIR/adapters/claude/hooks')"
  settings="$(printf '%s\n%s\n' "$settings" "$hooks" | jq -s "$MERGE_JQ")"
fi
if [ -f "$local_settings" ]; then
  settings="$(printf '%s' "$settings" | jq -s "$MERGE_JQ" "$local_settings" -)"
fi
wb_with_overlay "$settings" >"$local_settings.tmp"
mv "$local_settings.tmp" "$local_settings"

# 4. Company markers for the pre-commit check: local list, never committed.
markers="$(git -C "$WB_DIR" rev-parse --absolute-git-dir)/info/company-markers"
[ -f "$markers" ] || printf '# One word or regex per line: names that must never reach this personal repository.\n' >"$markers"

echo "workbench ready: $WB_DIR, FPF $(git -C "$FPF_DIR" rev-parse --short HEAD)"

# 5. A clone living in <project>/.workbench is connected to that project; a clone opened
#    on its own gets its instructions and skills through local files its git ignores.
if [ -n "$host" ]; then
  "$WB_DIR/scripts/attach.sh" "$host"
else
  printf '<!-- workbench: local file made by scripts/setup.sh, never commit it. -->\n@AGENTS.md\n' >"$WB_DIR/CLAUDE.local.md"
  [ -e "$WB_DIR/.claude/skills" ] || ln -s ../.agents/skills "$WB_DIR/.claude/skills"
fi
