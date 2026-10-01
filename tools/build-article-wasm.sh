#!/bin/sh
# Build the third-party programs used by vignettes/articles/real-world.Rmd.
#
# Usage: tools/build-article-wasm.sh
#
# Writes into vignettes/articles/wasm/ (excluded from the package tarball):
#   sqlite3.wasm  the SQLite shell, compiled from the official amalgamation
#   md2html.wasm  md4c's Markdown-to-HTML command, compiled from its tag
#   qjs.wasm      QuickJS-ng's own WASI build, downloaded from its release
# Every download is pinned and checksummed. wasi-sdk comes from $WASI_SDK,
# or is downloaded like in tools/build-wasi-fixtures.sh.
set -eu

SQLITE_VERSION="3530400"   # 3.53.4
SQLITE_YEAR="2026"
SQLITE_SHA256="1e71ddf93849c6a6ecf58b827c0692073d2dd7ee40196158068f7b29f422e87d"
MD4C_TAG="v0.6.0"
MD4C_COMMIT="7fc1815a5eeba2af7d6120a76202bf59f3b6e6e4"
QJS_TAG="v0.17.0"
QJS_SHA256="42a732a676ec2d93488c19411e0fad283bf72658fdad746f089914b523c783b1"
WASI_SDK_VERSION="34"

PKG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$PKG_ROOT/vignettes/articles/wasm"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
check() { # FILE SHA256
  got="$($SHA "$1" | cut -d' ' -f1)"
  [ "$got" = "$2" ] || { echo "checksum mismatch for $1: $got" >&2; exit 1; }
}

if [ -z "${WASI_SDK:-}" ]; then
  case "$(uname -s)-$(uname -m)" in
    Darwin-x86_64) platform="x86_64-macos" ;;
    Darwin-arm64) platform="arm64-macos" ;;
    Linux-x86_64) platform="x86_64-linux" ;;
    Linux-aarch64) platform="arm64-linux" ;;
    *) echo "build-article-wasm: unsupported platform; set WASI_SDK" >&2; exit 1 ;;
  esac
  curl -fsSL "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-$WASI_SDK_VERSION/wasi-sdk-$WASI_SDK_VERSION.0-$platform.tar.gz" \
    | tar xz -C "$TMP"
  WASI_SDK="$TMP/wasi-sdk-$WASI_SDK_VERSION.0-$platform"
fi
CC="$WASI_SDK/bin/clang --target=wasm32-wasip1 -O2 -s -ffile-prefix-map=$TMP=."

# SQLite: no threads, extensions or WAL (WASI has no mmap or dlopen), and a
# system() stub, since WASI has no shell for the .system command.
curl -fsSL -o "$TMP/sqlite.zip" "https://sqlite.org/$SQLITE_YEAR/sqlite-amalgamation-$SQLITE_VERSION.zip"
check "$TMP/sqlite.zip" "$SQLITE_SHA256"
(cd "$TMP" && unzip -q sqlite.zip)
printf 'int system(const char *command) { (void)command; return -1; }\n' > "$TMP/nosystem.c"
src="$TMP/sqlite-amalgamation-$SQLITE_VERSION"
# shellcheck disable=SC2086
$CC -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_WAL \
  -DSQLITE_OMIT_POPEN -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_GETPID \
  -D_WASI_EMULATED_PROCESS_CLOCKS -lwasi-emulated-signal -lwasi-emulated-getpid \
  -lwasi-emulated-process-clocks \
  "$src/shell.c" "$src/sqlite3.c" "$TMP/nosystem.c" -o "$OUT/sqlite3.wasm"

# md4c: the version macros normally come from CMake.
git clone -q --depth 1 --branch "$MD4C_TAG" https://github.com/mity/md4c.git "$TMP/md4c"
[ "$(git -C "$TMP/md4c" rev-parse HEAD)" = "$MD4C_COMMIT" ] || { echo "md4c $MD4C_TAG moved" >&2; exit 1; }
# shellcheck disable=SC2086
$CC -DMD_VERSION_MAJOR=0 -DMD_VERSION_MINOR=6 -DMD_VERSION_RELEASE=0 \
  -D_WASI_EMULATED_PROCESS_CLOCKS -lwasi-emulated-process-clocks -I"$TMP/md4c/src" \
  "$TMP/md4c/src/md4c.c" "$TMP/md4c/src/md4c-html.c" "$TMP/md4c/src/entity.c" \
  "$TMP/md4c/md2html/md2html.c" "$TMP/md4c/md2html/cmdline.c" -o "$OUT/md2html.wasm"

# QuickJS-ng: its own release build, unmodified.
curl -fsSL -o "$OUT/qjs.wasm" "https://github.com/quickjs-ng/quickjs/releases/download/$QJS_TAG/qjs-wasi.wasm"
check "$OUT/qjs.wasm" "$QJS_SHA256"

for f in sqlite3 md2html qjs; do
  echo "built vignettes/articles/wasm/$f.wasm ($(wc -c < "$OUT/$f.wasm" | tr -d ' ') bytes)"
done
