# WebAssembly modules for the pkgdown articles

These modules are used by `vignettes/articles/*.Rmd`. They are not part of
the R package: `vignettes/articles` is excluded from the tarball.

## Written for the articles

| File | Source | Built with |
|------|--------|-----------|
| `strings.wasm`, `mandelbrot.wasm`, `integrate.wasm`, `counter.wasm`, `untrusted.wasm` | the `.wat` file of the same name | `tools/build-fixtures.sh` (wabt 1.0.37) |
| `wc.wasm` (WASI program), `terrain.wasm` (WASI reactor library) | the `.c` file of the same name | `tools/build-wasi-fixtures.sh` (wasi-sdk 34) |

## Third-party software

Built by `tools/build-article-wasm.sh`, which pins and checksums every
download and builds byte-identically.

| File | Software | Version | Licence | How |
|------|----------|---------|---------|-----|
| `sqlite3.wasm` | [SQLite](https://sqlite.org) command-line shell | 3.53.4 | public domain | compiled from the official amalgamation with wasi-sdk 34 (no threads, extensions or WAL; `system()` stubbed) |
| `md2html.wasm` | [md4c](https://github.com/mity/md4c) `md2html` | 0.6.0 | MIT, Copyright © 2016-2026 Martin Mitáš | compiled from the `v0.6.0` tag with wasi-sdk 34 |
| `qjs.wasm` | [QuickJS-ng](https://github.com/quickjs-ng/quickjs) `qjs` | 0.17.0 | MIT, Copyright © 2017-2026 Fabrice Bellard, Charlie Gordon and the QuickJS-ng contributors | the project's own `qjs-wasi.wasm` release asset, unmodified |
