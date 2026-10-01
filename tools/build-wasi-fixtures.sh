#!/bin/sh
# Compile the WASI test programs and examples (C sources) with wasi-sdk.
#
# Usage: tools/build-wasi-fixtures.sh
#
# Builds tests/testthat/fixtures/wasi/*.c, inst/extdata/*-wasi.c and
# vignettes/articles/wasm/*.c into
# .wasm files next to them, which are committed. wasi-sdk is pinned and
# downloaded into a temporary directory (never installed), so the output is
# byte-identical across machines. Set WASI_SDK to use an existing copy of
# the same release instead.
set -eu

WASI_SDK_VERSION="34"
PKG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${WASI_SDK:-}" ]; then
  case "$(uname -s)-$(uname -m)" in
    Darwin-x86_64) platform="x86_64-macos" ;;
    Darwin-arm64) platform="arm64-macos" ;;
    Linux-x86_64) platform="x86_64-linux" ;;
    Linux-aarch64) platform="arm64-linux" ;;
    *) echo "build-wasi-fixtures: unsupported platform; set WASI_SDK" >&2; exit 1 ;;
  esac
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  url="https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-$WASI_SDK_VERSION/wasi-sdk-$WASI_SDK_VERSION.0-$platform.tar.gz"
  echo "Downloading wasi-sdk $WASI_SDK_VERSION ($platform) ..."
  curl -fsSL "$url" | tar xz -C "$TMP"
  WASI_SDK="$TMP/wasi-sdk-$WASI_SDK_VERSION.0-$platform"
fi

for src in "$PKG_ROOT"/tests/testthat/fixtures/wasi/*.c "$PKG_ROOT"/inst/extdata/*-wasi.c \
           "$PKG_ROOT"/vignettes/articles/wasm/*.c; do
  [ -e "$src" ] || continue
  out="${src%.c}.wasm"
  # A source that needs extra flags names them on its first line:
  #   // wasi-sdk: -mexec-model=reactor
  flags="$(sed -n '1s|^// wasi-sdk: ||p' "$src")"
  # shellcheck disable=SC2086 # flags are deliberately split
  "$WASI_SDK/bin/clang" --target=wasm32-wasip1 -Oz -s $flags \
    -ffile-prefix-map="$PKG_ROOT"=. -o "$out" "$src"
  echo "built ${out#"$PKG_ROOT"/} ($(wc -c < "$out" | tr -d ' ') bytes)"
done
