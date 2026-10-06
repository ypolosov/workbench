#!/bin/sh
# Short-lived local app-server calls; stdin stays open until a reply arrives.
wb_codex_rpc() {
  wb_rpc_request="$(printf '%s' "$1" | jq -c '.')"
  wb_rpc_stage="$(mktemp -d "${TMPDIR:-/tmp}/workbench-rpc.XXXXXX")"
  wb_rpc_done="$wb_rpc_stage/done"
  {
    printf '%s\n' '{"id":1,"method":"initialize","params":{"clientInfo":{"name":"workbench_installer","title":"workbench","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}'
    printf '%s\n' '{"method":"initialized"}' "$wb_rpc_request"
    wb_rpc_wait=0
    while [ ! -f "$wb_rpc_done" ] && [ "$wb_rpc_wait" -lt 150 ]; do
      sleep 0.1
      wb_rpc_wait=$((wb_rpc_wait + 1))
    done
  } | codex app-server --stdio >"$wb_rpc_stage/output" 2>"$wb_rpc_stage/errors" &
  wb_rpc_pid=$!
  wb_rpc_reply=""
  wb_rpc_poll=0
  while [ "$wb_rpc_poll" -lt 150 ]; do
    wb_rpc_reply="$(jq -c 'select(.id == 2)' "$wb_rpc_stage/output" 2>/dev/null || true)"
    [ -z "$wb_rpc_reply" ] || break
    sleep 0.1
    wb_rpc_poll=$((wb_rpc_poll + 1))
  done
  : >"$wb_rpc_done"
  wait "$wb_rpc_pid" || true
  [ -n "$wb_rpc_reply" ] || return 1
  printf '%s\n' "$wb_rpc_reply"
  printf '%s' "$wb_rpc_reply" | jq -e 'has("result")' >/dev/null
}

wb_codex_list_hooks() {
  wb_hooks_cwds="$(printf '%s\n' "$@" | while IFS= read -r wb_hook_cwd; do wb_native_path "$wb_hook_cwd"; done | jq -Rsc 'split("\n") | map(select(length > 0))')"
  wb_codex_rpc "$(jq -n --argjson cwds "$wb_hooks_cwds" '{id: 2, method: "hooks/list", params: {cwds: $cwds}}')"
}

wb_codex_trust() {
  command -v codex >/dev/null 2>&1 || return 0
  # The caller obtained consent for these folders and these four workbench hooks.
  wb_codex_projects="$(printf '%s\n' "$@" | while IFS= read -r wb_hook_cwd; do wb_native_path "$wb_hook_cwd"; done | jq -Rsc 'split("\n") | map(select(length > 0)) | map({key: ., value: {trust_level: "trusted"}}) | from_entries')"
  wb_codex_config="$(wb_native_path "$(dirname "$(wb_codex_agents_md)")/config.toml")"
  wb_codex_rpc "$(jq -n --argjson projects "$wb_codex_projects" --arg file "$wb_codex_config" '{id: 2, method: "config/batchWrite", params: {filePath: $file, edits: [{keyPath: "projects", value: $projects, mergeStrategy: "upsert"}]}}')" >/dev/null || return 1
  wb_hooks_listing="$(wb_codex_list_hooks "$@")" || return 1
  wb_hook_states="$(printf '%s' "$wb_hooks_listing" | jq --argjson cwds "$(printf '%s' "$wb_codex_projects" | jq 'keys')" '
    [.result.data[].hooks[] | select(.handlerType == "command") |
     select((.sourcePath | gsub("\\\\"; "/")) as $source |
       any($cwds[]; $source == ((. | gsub("\\\\"; "/")) + "/.codex/hooks.json"))) |
     select((.command | startswith("workbench.cmd --hook ")) or
       (.command | startswith("WB_AGENT=codex sh ") and contains("adapters/claude/hooks/"))) |
     {key: .key, value: {trusted_hash: .currentHash, enabled: true}}] | from_entries')"
  [ "$wb_hook_states" != '{}' ] || return 1
  wb_codex_rpc "$(jq -n --argjson state "$wb_hook_states" --arg file "$wb_codex_config" '{id: 2, method: "config/batchWrite", params: {filePath: $file, edits: [{keyPath: "hooks.state", value: $state, mergeStrategy: "upsert"}]}}')" >/dev/null
}
