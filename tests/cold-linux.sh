#!/bin/sh
# Run only in a disposable minimal Linux container, with a read-only test fixture.
set -eu
# Copy the fixture so Git sees repositories owned by this container's user.
fixture=$1
mkdir -p "$fixture"
cp -R /test-fixture/. "$fixture/"
template="$fixture/template"
if command -v git >/dev/null 2>&1 || command -v jq >/dev/null 2>&1; then
  printf 'cold test requires Git and jq to be absent\n' >&2
  exit 1
fi
cat "$template/install.sh" | sh -s -- --template "file://$template" --local --yes --no-launch
env HOME="$HOME" PATH=/usr/bin:/bin bash -l -c 'command -v workbench && command -v jq && workbench doctor --json'
