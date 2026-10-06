#!/bin/sh
# Fetch the current installer: an old installed CLI must not implement new migrations.
set -eu
WB_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
template="${WORKBENCH_TEMPLATE:-$(git -C "$WB_DIR" remote get-url template)}"
bin_dir="$HOME/.local/bin"
if command -v jq >/dev/null 2>&1 && [ -f "$WB_DIR/.runtime/install.json" ]; then
  bin_dir="$(jq -r '.binDir // empty' "$WB_DIR/.runtime/install.json")"
  [ -n "$bin_dir" ] || bin_dir="$HOME/.local/bin"
fi
assume_yes=0
core_only=0
project=""
while [ $# -gt 0 ]; do
  case $1 in
    --template)
      template=${2:?--template requires a URL}
      shift 2
      ;;
    --bin-dir)
      bin_dir=${2:?--bin-dir requires a folder}
      shift 2
      ;;
    --project)
      project=${2:?--project requires a folder}
      shift 2
      ;;
    --yes | -y)
      assume_yes=1
      shift
      ;;
    --core-only)
      core_only=1
      shift
      ;;
    --no-launch) shift ;;
    -h | --help)
      printf 'workbench update [--yes] [--project <folder>] [--template <URL>]\n'
      exit 0
      ;;
    *)
      printf 'workbench update: unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done
snapshot="$(mktemp -d "${TMPDIR:-/tmp}/workbench-update.XXXXXX")"
git clone -q "$template" "$snapshot/source"
# Both the installer and its helpers use exactly this fetched revision.
set -- --dir "$WB_DIR" --template "$snapshot/source" --bin-dir "$bin_dir" --no-launch
[ "$assume_yes" != 1 ] || set -- "$@" --yes
[ "$core_only" != 1 ] || set -- "$@" --core-only
[ -z "$project" ] || set -- "$@" --project "$project"
exec sh "$snapshot/source/install.sh" "$@"
