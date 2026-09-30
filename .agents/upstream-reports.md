# Reports to toywasm upstream (#41)

Issues found while vendoring toywasm v76.0.0, each worked around in
`tools/vendor/patch-for-r.sh`. Filed on 2026-09-30, from the fork
pedrobtz/toywasm. When one is merged and released, re-vendor and drop the
matching substitution.

| Upstream | What | Local workaround |
|---|---|---|
| [PR #359](https://github.com/yamt/toywasm/pull/359) | `module_print_stats()` doesn't compile with `TOYWASM_ENABLE_WRITER=OFF` (`code_size`) | "code_size declaration" |
| [PR #360](https://github.com/yamt/toywasm/pull/360) | mingw-w64 build: `vasprintf` redefinition; `__printflike` flags `%zu` | "vasprintf fallback on mingw", "__printflike on mingw" |
| [PR #361](https://github.com/yamt/toywasm/pull/361) | NULL passed to `qsort`/`memset`/`memcpy` (UBSan `nonnull-attribute`) | "qsort of no exports", "cells_zero()/cells_copy() of zero cells" |
| [Issue #362](https://github.com/yamt/toywasm/issues/362) | NULL + 0 arithmetic on empty vectors (UBSan `pointer-overflow`, which upstream deliberately disables) | "preallocate the execution vectors", "ARRAY_FOREACH over a NULL array" |

Not reported:

- `host_instance.h` has no include guard. Most of toywasm's headers don't:
  that is the project's style, not a bug. nanowasm includes it once
  (`src/nanowasm.h`).
- The GNU statement expression in `decode.h` and assert-only variables:
  upstream builds with `-Wno-gnu-statement-expression -Wno-unused-variable`
  on purpose. These only matter under CRAN's flags, so they stay local
  changes.
