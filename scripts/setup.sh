#!/bin/sh
# Prepares the personal base of this machine: the pinned FPF worktree in .fpf, git hooks
# and the local agent files for sessions opened in the base itself (Claude Code and
# Cursor read .claude, Codex reads .codex). install.sh runs it; running it again is safe.
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
# the worktree's own link relative (as git writes for submodules), so the pair also
# works when the base is mounted into a devcontainer. Native relative worktree paths
# need git 2.48+.
git -C "$WB_DIR" worktree repair "$FPF_DIR" >/dev/null 2>&1 || echo "WARN: git worktree repair failed for .fpf" >&2
worktree_id="$(basename "$(git -C "$FPF_DIR" rev-parse --absolute-git-dir)")"
printf 'gitdir: ../.git/worktrees/%s\n' "$worktree_id" >"$FPF_DIR/.git"
# A base that took a template update with another pinned edition moves .fpf to it; a
# worktree with local changes stays where it is, so nothing in it is lost.
current="$(git -C "$FPF_DIR" rev-parse HEAD)"
if [ "$current" != "$fpf_commit" ]; then
  if git -C "$FPF_DIR" checkout -q --detach "$fpf_commit"; then
    echo "workbench: FPF переведён на закреплённое издание $(git -C "$FPF_DIR" rev-parse --short HEAD)"
  else
    echo "WARN: .fpf is at $current, pinned edition is $fpf_commit" >&2
  fi
fi

# 2. Git hooks work for any agent and for a human. Pulls merge: the base keeps its own
#    history on top of the template's, and that history must never be rewritten.
git -C "$WB_DIR" config core.hooksPath .githooks
git -C "$WB_DIR" config pull.rebase false
chmod +x "$WB_DIR"/adapters/claude/hooks/*.sh "$WB_DIR"/.githooks/* "$WB_DIR"/scripts/*.sh "$WB_DIR"/bin/workbench

# 3. Sessions opened in the base itself keep Claude Code auto-memory here and get the
#    adapter's hooks and the personal overlay; Cursor runs the same hooks, and Codex gets
#    them in its own file. All of it is local: autoMemoryDirectory is ignored in a
#    committed settings.json.
mkdir -p "$WB_DIR/.claude" "$WB_DIR/.codex"
local_settings="$WB_DIR/.claude/settings.local.json"
# Expanded by the shell that runs each hook, not here.
# shellcheck disable=SC2016
hooks="$(wb_hooks_json '"$CLAUDE_PROJECT_DIR/adapters/claude/hooks/%s"')"
settings="$(printf '%s\n%s\n' "$(jq -n --arg dir "$WB_DIR/memory" '{autoMemoryDirectory: $dir}')" "$hooks" | jq -s "$MERGE_JQ")"
if [ -f "$local_settings" ]; then
  settings="$(printf '%s' "$settings" | jq -s "$MERGE_JQ" "$local_settings" -)"
fi
wb_with_overlay "$settings" >"$local_settings.tmp"
mv "$local_settings.tmp" "$local_settings"
codex_hooks="$WB_DIR/.codex/hooks.json"
settings="$(wb_codex_hooks_json "$WB_DIR" adapters/claude/hooks)"
if [ -f "$codex_hooks" ]; then
  # The base's own hooks of an earlier run go first: a changed command would stay twice.
  own="$(jq '.hooks |= with_entries(.value |= (map(.hooks |= map(select((.command // "") | contains("adapters/claude/hooks/") | not))) | map(select(.hooks | length > 0))))' "$codex_hooks")"
  settings="$(printf '%s\n%s\n' "$own" "$settings" | jq -s "$MERGE_JQ")"
fi
printf '%s\n' "$settings" >"$codex_hooks.tmp"
mv "$codex_hooks.tmp" "$codex_hooks"

# 4. Company markers for the pre-commit check: local list, never committed.
markers="$(git -C "$WB_DIR" rev-parse --absolute-git-dir)/info/company-markers"
[ -f "$markers" ] || printf '# One word or regex per line: names that must never reach this personal repository.\n' >"$markers"

# 5. Instructions and skills for sessions opened in the base itself; git ignores them.
printf '<!-- workbench: local file made by scripts/setup.sh, never commit it. -->\n@AGENTS.md\n' >"$WB_DIR/CLAUDE.local.md"
[ -e "$WB_DIR/.claude/skills" ] || [ -L "$WB_DIR/.claude/skills" ] || wb_link ../.agents/skills "$WB_DIR/.claude/skills"

echo "workbench: база готова: $WB_DIR, FPF $(git -C "$FPF_DIR" rev-parse --short HEAD)"
