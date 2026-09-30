#!/bin/sh
# Run a subset of the WebAssembly spec test suite against nanowasm.
#
# Usage: tools/spec/run.sh [workdir]
#
# Fetches the spec test suite at a pinned commit, converts the .wast files
# listed in tools/spec/files.txt to JSON + .wasm with wast2json, and runs
# tools/spec/runner.R on them with the installed nanowasm. wast2json comes
# from $WAST2JSON if set, otherwise from the pinned wabt release (Linux).
# Needs R with nanowasm and jsonlite installed.
set -eu

TESTSUITE_COMMIT="b464a4cd100d98175ae6e3890db89a2e6c8302f7"
WABT_VERSION="1.0.37"
PKG_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${1:-$(mktemp -d)}"
mkdir -p "$WORK"

if [ -z "${WAST2JSON:-}" ]; then
  if [ ! -x "$WORK/wabt-$WABT_VERSION/bin/wast2json" ]; then
    curl -fsSL "https://github.com/WebAssembly/wabt/releases/download/$WABT_VERSION/wabt-$WABT_VERSION-ubuntu-20.04.tar.gz" \
      | tar xz -C "$WORK"
  fi
  WAST2JSON="$WORK/wabt-$WABT_VERSION/bin/wast2json"
fi

if [ ! -d "$WORK/testsuite" ]; then
  git init -q "$WORK/testsuite"
  git -C "$WORK/testsuite" fetch -q --depth 1 https://github.com/WebAssembly/testsuite.git "$TESTSUITE_COMMIT"
  git -C "$WORK/testsuite" checkout -q FETCH_HEAD
fi

rm -rf "$WORK/json"
mkdir -p "$WORK/json"
unconverted=""
for name in $(grep -v '^#' "$PKG_ROOT/tools/spec/files.txt"); do
  if ! (cd "$WORK/json" && "$WAST2JSON" --enable-tail-call "$WORK/testsuite/$name.wast" -o "$name.json" >/dev/null 2>&1); then
    unconverted="$unconverted $name"
  fi
done
if [ -n "$unconverted" ]; then
  echo "wast2json $WABT_VERSION could not convert:$unconverted" >&2
  exit 1
fi

Rscript "$PKG_ROOT/tools/spec/runner.R" "$WORK/json" "$PKG_ROOT/tools/spec/known-failures.txt"
