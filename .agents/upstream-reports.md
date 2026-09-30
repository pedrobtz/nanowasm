# Draft reports for toywasm upstream (#41)

Issues found while vendoring toywasm v76.0.0 into nanowasm. Each is worked
around in `tools/vendor/patch-for-r.sh`. **Not posted yet:** posting to
yamt/toywasm needs the maintainer's go-ahead.

---

## 1. `module_print_stats()` doesn't compile with `TOYWASM_ENABLE_WRITER` off

`lib/module.c`, `module_print_stats()`: `code_size` is declared inside
`#if defined(TOYWASM_ENABLE_WRITER)`, but used unconditionally
(`code_size += expr_end(e) - e->start;` and the `nbio_printf` below).
With `-DTOYWASM_ENABLE_WRITER=OFF` the file fails to compile ("use of
undeclared identifier 'code_size'"). `expr_end()` is always available, so
the declaration can be unconditional.

## 2. `report.c` redefines `vasprintf` on mingw-w64

`lib/report.c` defines `vasprintf()` under `#if defined(_WIN32)`. mingw-w64's
`<stdio.h>` already defines it (with `_GNU_SOURCE`), so gcc on mingw-w64
(e.g. R's Rtools 4.5) fails with "redefinition of 'vasprintf'". Suggest
`#if defined(_WIN32) && !defined(__MINGW32__)`.

## 3. `__printflike` flags `%zu` on mingw

On mingw-w64, `__attribute__((format(printf, ...)))` checks against the
Microsoft runtime's printf, which gcc believes has no `%z`, so every
`size_t` in a log format warns (`-Wformat`). The strings go through
mingw's C99-conforming `vasprintf`, so `format(gnu_printf, ...)` is the
right check there.

## 4. Undefined behaviour on empty vectors (UBSan)

Vectors start with `p == NULL` and are allocated on first use, but several
places form pointers from them while still empty, which is undefined
behaviour even with a zero offset. clang's `-fsanitize=undefined` reports
"applying zero offset to null pointer" at, for example:

- `exec.c` `frame_locals()` / `frame_enter()`: `&VEC_ELEM(ctx->locals, idx)`
  for a function with no params or locals;
- `exec.c` `exec_push_vals()` / `exec_pop_vals()` / the main loop:
  `&VEC_NEXTELEM(ctx->stack)` on an empty stack;
- `insn.c`: `ctx->stack.p + ctx->stack.psize` in an assertion;
- `util.h` `ARRAY_FOREACH`: `a + sz` with `a == NULL`.

Also `memset`/`memcpy` with a NULL pointer and zero length in
`cells_zero()`/`cells_copy()`, and `qsort(NULL, 0, ...)` in
`module_load_into()` for a module without exports (glibc declares the
argument non-null; gcc's UBSan reports it).

nanowasm's workaround: preallocate one element of `frames`, `stack`,
`labels` and `locals` in `exec_context_init()`, guard `ARRAY_FOREACH`
against NULL, and skip `cells_*` and `qsort` for zero counts.

## 5. Missing include guard in `host_instance.h`

`lib/host_instance.h` has no include guard, so including it twice (directly
and through another header) fails with "redefinition of 'host_func'".
