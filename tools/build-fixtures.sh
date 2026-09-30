#!/bin/sh
# Compile every .wat fixture to .wasm next to it.
#
# Usage: tools/build-fixtures.sh
#
# The .wasm files are committed, so neither tests nor users need wabt. After
# editing a .wat, rerun this and commit both files; `git status` then shows
# any binary that was out of date. wabt is pinned so the output is
# byte-identical across machines:
# a wat2wasm on PATH is used only if it is that version, otherwise the npm
# build of the same release runs through npx.
#
# A fixture that needs extra wat2wasm flags names them on its first line:
#   ;; wat2wasm: --enable-multi-memory
set -eu

WABT_VERSION="1.0.37"
PKG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if command -v wat2wasm >/dev/null 2>&1 &&
   [ "$(wat2wasm --version 2>/dev/null)" = "$WABT_VERSION" ]; then
  wat2wasm () { command wat2wasm "$@"; }
else
  wat2wasm () { npx --yes -p "wabt@$WABT_VERSION" wat2wasm "$@"; }
fi

for dir in tests/testthat/fixtures inst/extdata vignettes/articles/wasm; do
  for wat in "$PKG_ROOT/$dir"/*.wat; do
    [ -e "$wat" ] || continue
    flags="$(sed -n '1s/^;; wat2wasm: //p' "$wat")"
    # shellcheck disable=SC2086 # flags are deliberately split
    wat2wasm $flags "$wat" -o "${wat%.wat}.wasm"
    echo "built $dir/$(basename "${wat%.wat}.wasm")"
  done
done
