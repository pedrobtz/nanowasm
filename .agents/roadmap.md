# nanowasm roadmap to 0.1.0

Companion to [design.md](design.md). This file plans the first release,
**nanowasm 0.1.0 on CRAN**. Work after the release is only listed briefly at
the end.

How to use this file:

- CI uses only reusable workflows from pedrobtz/r-actions. Checks without
  one there (fixture rebuild, spec tests) are scripts under `tools/`, run
  locally before a release.
- Milestones run in order. Each one ends in a mergeable state with CI green
  (quick profile on every PR; add the `full-ci` label to the PR that closes
  a milestone).
- Each task is a GitHub issue under its milestone. PRs close them with
  `Closes #n`, and the same PR ticks the box here. Add user-facing changes to
  `NEWS.md` under the development heading.
- The version stays at 0.0.0.9000 until the 0.1.0 release. The per-milestone
  dev bumps (0.0.0.9001–.9006) were folded back into it on 2026-09-30.
  pkgdown runs in development mode (`auto`): until 0.1.0 the site builds at
  the root marked "unreleased"; from 0.1.0.9000 the dev site builds into
  `dev/`, with the released site at the root.
- Scope changes go in §1 first, in their own PR, and not quietly in a task list.

---

## 1. Release scope

### What 0.1.0 is

A dependency-free way to load a **pure-computation** WebAssembly module in R,
call its exports, move data through its linear memory, give it R callbacks,
and run it under enforced limits. Every failure surfaces as a classed R
condition.

### In scope

| Area | 0.1.0 surface |
|---|---|
| Modules | `wasm_module()`, `wasm_validate()`, `wasm_exports()`, `wasm_imports()`, `print()` |
| Instances & calls | `wasm_instantiate()`, `wasm_call()`, `inst$fn(...)`, `names(inst)`, `wasm_global()` / `wasm_global<-` |
| Values | i32, i64, f32, f64 as in design §4.3 |
| Memory | `wasm_memory()`, `wasm_memory_size()`, `wasm_memory_grow()`, `wasm_read()`, `wasm_write()`, `wasm_read_string()`, `wasm_write_string()` |
| Imports | `wasm_func()`, nested `imports` list, `caller` argument with memory access |
| Limits | `wasm_limits()` (memory, frames, stack, timeout), the `nanowasm.limits` option, Ctrl-C |
| WASI | `wasm_wasi()`, `wasm_instantiate(wasi = )`, `wasm_wasi_start()`, `wasm_wasi_output()`, `wasm_run()`: preview 1 in R, with preopened directories (added 2026-10-01, M6) |
| Conditions | the full class tree in design §8 |
| Wasm features | MVP + bulk memory, reference types (inside the module only), multi-value, tail calls, extended const, multi-memory, name section |
| Platforms | Linux, macOS, Windows (Rtools), R ≥ 4.3 |

### Out of scope (explicitly deferred)

SIMD, exception handling, threads/shared memory, WASI preview 2 and sockets,
`funcref`/`externref` at the R boundary, lossless i64, re-entrant callbacks,
linking instances to each other, allocator helpers, memory indexing sugar,
performance tuning.

A module that needs any of these must fail with a **clear error that names the
missing feature**, whether at load, link or call time. It must never crash or
behave wrongly without saying so.

### Open questions settled for 0.1.0

These resolve design §12 for this release only. Each can be revisited later.

| # | Question | 0.1.0 answer |
|---|---|---|
| 12.1 | Lossless i64 | Double only. Values beyond ±2^53 raise `nanowasm_precision_error`. |
| 12.2 | Re-entrancy | Forbidden, with a clear error. |
| 12.3 | Instance after a trap or timeout | Stays usable. The docs warn that its state may be partly updated. |
| 12.4 | Memory indexing sugar | No. Only `wasm_read()`/`wasm_write()`. |
| 12.5 | Sharing between instances | No. |
| 12.6 | Upstream patches | Offered upstream, but a merge upstream is not required for release. |

---

## 2. Milestones

### M0: Honest skeleton (0.0.0.9001)

Tracked in [milestone M0](https://github.com/pedrobtz/nanowasm/milestone/1) (issues #2–#5).

- [x] `DESCRIPTION`: real Title/Description, `Authors@R`, `Depends: R (>= 4.3)`,
      `URL` (GitHub + pkgdown), `BugReports`. (#2)
- [x] README: pitch, install, "experimental" status, sandbox caveat (design §9). (#4)
- [x] Remove the template test; a namespace smoke test keeps `test_check()`
      happy until M1 adds real tests. (#5)
- [x] `.Rbuildignore`: `^\.agents$`.
- [x] `NEWS.md` uses numeric version headings: R's NEWS parser does not
      recognise "(development version)" and `R CMD check` NOTEs it.

`inst/COPYRIGHTS` and the toywasm `cph` entry moved to M1 (#3): they would
describe code that isn't in the tree until toywasm is vendored.

**Exit:** `devtools::check()` gives 0/0/0 on the empty package.

### M1: toywasm builds everywhere (0.0.0.9002)

Tracked in [milestone M1](https://github.com/pedrobtz/nanowasm/milestone/2) (issues #6–#13).

- [x] `inst/COPYRIGHTS` + `inst/TOYWASM_LICENSE`, and toywasm's author as
      `cph` in `Authors@R`. (#3)
- [x] `tools/vendor-toywasm.sh` + `tools/vendor/` (file list, `patch-for-r.sh`,
      `VENDORED`, `manifest.tsv`, `checksums.sha256`, `verify`). Vendors
      **v76.0.0**. The r-actions `vendor.yml` guard runs on PRs, and
      `vendor-upstream.yml` runs weekly. (#6)
- [x] `tools/` does not ship in the tarball, following the sibling packages.
- [x] Hand-written `src/toywasm_config.h`. `toywasm_version.h` is generated,
      and `toywasm_config.c` is not needed (only upstream's CLI uses it). (#7)
- [x] Sources pruned to 32 `.c` / 56 `.h`, with no stubs needed. (#8)
- [x] `src/toywasm_shim.c` replaces `xlog.c` and `nbio.c` (all output
      discarded). (#9)
- [x] `Makevars` / `Makevars.win`, `init.c` with registration, `useDynLib`,
      and `toywasm_version()` (internal) with a test. (#10)
- [x] Symbol check: covered by `R CMD check`'s "compiled code" WARNING, which
      CI already fails on, so no separate `nm` step. (#12)
- [x] Zero warnings under clang `-std=gnu23 -O3 -Wall -pedantic` locally.
      `-Wextra` was dropped as a target, because CRAN doesn't use it and it
      only adds `-Wunused-parameter` on callbacks. gcc is checked in CI. (#13)
- [ ] Windows (Rtools) build green in CI. (#11)

**Exit:** a full-profile CI run is green on all three OSes. The installed
package is under 5 MB.
**Biggest risk in the release:** Windows portability (`timeutil.c`, atomics).
Hit it first. If it needs more than small patches, raise it before M2.

### M2: Load and call (0.0.0.9003)

Tracked in [milestone M2](https://github.com/pedrobtz/nanowasm/milestone/3) (issues #14–#22).

- [x] Fixture pipeline: `.wat` + committed `.wasm`, `tools/build-fixtures.sh`
      (wabt 1.0.37 through npx if not installed). CI uses only
      pedrobtz/r-actions workflows, so the rebuild check runs locally
      (reproducible byte for byte), not in CI. (#14)
- [x] `wasm_module()` / `wasm_validate()`, keeping a private copy of the
      bytes, plus the `nanowasm.max_module_size` limit (64 MB). (#15)
- [x] `wasm_exports()` / `wasm_imports()` / `print` / signature formatting.
      Exports are sorted by name; an implicit max is not shown. (#16)
- [x] `wasm_instantiate()` without imports (link error listing them) and the
      start function. (#17)
- [x] `wasm_call()`, `$`, `[[`, `names()`. Value mapping and edge-case
      tests. (#18, #19)
- [x] Condition machinery (`nanowasm_failure` data → `nw_check()`):
      validation, argument/precision, unsupported, trap + `trap_id` table,
      invalid object, runtime error. (#20)
- [x] Reference-counted C objects, since finaliser order is not guaranteed.
      Lifetime tests (`gc()`, `gctorture`, `saveRDS` round trip). (#21)
- [x] `inst/extdata/add.wasm`, `fib.wasm` (+ `.wat`, README), and roxygen
      examples. (#22)
- [x] Default limits of 10,000 frames and 1e6 stack cells until M3 makes them
      configurable, because toywasm's defaults are unlimited.

**Exit:** `inst$fib(25L)` works. Every trap fixture maps to the right class.
Coverage of `R/` is ≥ 90%.

### M3: Memory and limits (0.0.0.9004)

Tracked in [milestone M3](https://github.com/pedrobtz/nanowasm/milestone/4) (issues #23–#28).

- [x] Memory API (design §4.4): `wasm_memory()`, `wasm_read()`/`wasm_write()`
      for raw/i8/u8/i16/u16/i32/u32/i64/u64/f32/f64, bounds-checked, endian-safe,
      writes validated before any byte changes; `wasm_read_string()` /
      `wasm_write_string()` (UTF-8, NUL-terminated); `wasm_memory_size(unit=)`,
      `wasm_memory_grow()`. (#23)
- [x] `wasm_global()` get/set. (#24)
- [x] `wasm_limits()` + `nanowasm.limits` option: per-instance `mem_context`
      limit (covers memories, tables and call stacks) and `exec_options`. (#25)
- [x] Timeouts and Ctrl-C through toywasm's user-interrupt restart, with no
      patch: `nanowasm_timeout`, and Ctrl-C → base `interrupt`. Ctrl-C is
      tested automatically on Unix by sending SIGINT to the R process. (#26)
- [x] Classes `nanowasm_stack_exhausted` (frames and stack cells),
      `nanowasm_memory_limit`, `nanowasm_out_of_bounds` (traps and R-side
      accesses), plus `nanowasm_reentry_error` (a busy flag per instance).
- [x] Hostile fixtures: infinite loop and start function, unbounded
      recursion (frames and stack cells), `memory.grow` bomb, grow-and-touch,
      table growth, and a 100M-element table at instantiation. (#27)
- [x] Example: `inst/extdata/sum.wasm` (bump allocator + `sum_f64`), used in
      README, examples and tests. (#28)

**Exit:** no fixture can crash, hang or exhaust the memory of the R session.
Ctrl-C has been checked by hand on all three OSes.

### M4: Host functions (0.0.0.9005)

Tracked in [milestone M4](https://github.com/pedrobtz/nanowasm/milestone/5) (issues #29–#34).

- [x] `wasm_func()` and the `imports` list. Link errors report every missing
      import, any non-function import, and mismatched signatures side by side
      (`$missing`, `$mismatch`). (#29)
- [x] Trampoline + per-import binding: each import's `funcinst` has its own
      `host_instance`, the binding's first member. The import object is
      built directly, because toywasm's helper shares one `host_instance`. (#30)
- [x] Safe R evaluation: the R wrapper returns errors as values, and
      everything else, including R allocation during conversion, runs under
      `R_UnwindProtect`, whose cleanup longjmps back into the trampoline. The
      trampoline traps, and `R_ContinueUnwind` resumes the jump after toywasm
      has unwound (`nw_finish_run()`). (#31)
- [x] `nanowasm_host_error` with `$parent`; return values checked (type,
      length, range, list for several results); i64 arguments beyond 2^53
      give `nanowasm_precision_error`.
- [x] `caller` formal → `nanowasm_caller` with `memory()`, invalidated after
      the host call returns. (#32)
- [x] Re-entry → `nanowasm_host_error` whose parent is a
      `nanowasm_reentry_error`. (#33)
- [x] Tests: error, warning caught outside, restart, custom condition,
      Ctrl-C in a callback (SIGINT, Unix), re-entry, calling another
      instance, `gc()` and `gctorture` in callbacks, bad returns, the start
      function calling imports.
- [x] Example: `inst/extdata/log.wasm` calls `env.log(ptr, len)`. (#34)
- [x] `native-checks` workflow (pulled forward from M5, #35): ASan + UBSan,
      valgrind, LTO, gctorture (step 100), rchk, `-fanalyzer` (vendored tree
      excluded), CRAN special checks.

**Exit:** every non-local exit from a callback leaves the instance usable.
Clean under ASan.

### M5: Release hardening (0.0.0.9006 → 0.1.0)

Tracked in [milestone M5](https://github.com/pedrobtz/nanowasm/milestone/6) (issues #35–#42).

Must-have:

- [x] Sanitizer CI (ASan + UBSan) and valgrind on the full profile (added in
      M4, `native-checks.yml`). A local ASan/UBSan run of every fixture
      export found NULL + 0 undefined behaviour in toywasm, which is fixed in
      `patch-for-r.sh`. (#35)
- [x] Fuzzing: `tools/fuzz/harness.c` (decode, validate, instantiate, with
      toywasm's real assertions on) run by the r-actions `fuzz.yml`, for
      2 minutes on each push and 30 minutes weekly, with the fixtures as
      seeds and a Wasm dictionary. It also builds as a replay driver
      (`-DNANOWASM_FUZZ_MAIN`) where libFuzzer is missing. (#36)
- [x] Getting-started vignette, `vignette("nanowasm")`: load → call →
      memory → imports → limits and conditions → sandbox → getting
      modules. (#37)
- [x] Documentation on every export, with runnable examples (no `\dontrun`),
      a pkgdown reference grouped by area, and a package help page. (#38)
- [x] What the sandbox guarantees and what it does not: in the vignette and
      the README. (#39)
- [x] `cran-extrachecks` pass: install instructions, 'toywasm' named in
      Description, `cran-comments.md`, full list of local changes in
      `inst/COPYRIGHTS`; `urlchecker` clean.

Should-have:

- [x] Spec-test runner in `tools/spec/` (`run.sh`, run locally before a
      release, since CI uses only r-actions): 69 core files from
      WebAssembly/testsuite at a pinned commit, converted by wabt 1.0.37.
      **18,013 commands pass, 0 fail**, and 6,365 are skipped as not
      expressible through R (i64 beyond 2^53, NaN payloads,
      references, non-function imports, text-format assertions). New
      failures, or known ones that start passing, make the run fail. (#40)
- [x] Vendoring fixes reported to toywasm: PRs yamt/toywasm#359 (no-writer
      build), #360 (mingw-w64), #361 (NULL to qsort/memset/memcpy) and issue
      #362 (NULL + 0 on empty vectors). See `.agents/upstream-reports.md`.
      (#41)

**Exit:** see §3.

---

### M6: WASI

Added on 2026-10-01 at the maintainer's request: WASI lands before 0.1.0,
with preopened directories. Tracked in
[milestone M6](https://github.com/pedrobtz/nanowasm/milestone/7) (issues #52–#56).

- [x] Core: `wasm_wasi()`, `wasm_instantiate(wasi = )` (links all 46
      preview-1 functions; calls a reactor's `_initialize`),
      `wasm_wasi_start()` (exit status via `proc_exit`), `wasm_wasi_output()`,
      `wasm_run()`. (#52)
- [x] Arguments, environment, clocks, `random_get` (R's RNG), `poll_oneoff`
      sleeps, `sched_yield`; stdin from character or raw; stdout/stderr to the
      console (UTF-8-safe), captured or discarded. (#53)
- [x] Preopened directories (`dirs`), read-only unless `writable = TRUE`;
      open/read/write/pread/pwrite/seek/tell/readdir/stat/truncate/mkdir/
      rmdir/unlink/rename/set-times; no escape through `..`, absolute paths
      or symlinks. (#54)
- [x] Test programs in C built with a pinned wasi-sdk 34
      (`tools/build-wasi-fixtures.sh`, downloaded to a temporary directory),
      plus a WAT reactor and a generated WAT probe that re-exports every WASI
      function for direct tests; 286 WASI expectations, `R/wasi.R` 98%
      covered. toywasm's own 1 MB WASI build runs inside nanowasm (checked
      locally). (#55)
- [x] Docs: vignette section, README, `?wasm_wasi`/`?wasm_run` examples
      (`hello-wasi.wasm`, `cat-wasi.wasm`), a `wc` WASI example in the
      pkgdown article, design §10. (#56)

**Exit:** WASI programs run on Linux, macOS and Windows with every check green.

---

### M7: Diagnostics and exceptions

Added on 2026-10-01: the three toywasm capabilities that were easiest to
expose, reviewed together with the maintainer. Tracked in
[milestone M7](https://github.com/pedrobtz/nanowasm/milestone/8) (issues #59–#61),
one PR each.

- [x] `wasm_stats()`: bytes allocated for the instance (current, peak,
      limit; peak tracking turned on in `toywasm_config.h`), and cumulative
      counts of runs, calls, host calls and branches. (#59)
- [x] Traps name the function they happened in (name section, else export
      or import name, else `func[N]`) and carry `func`, `backtrace`
      (innermost first, at most 64) and `depth`; so do timeouts and host
      errors. (#60)
- [ ] Exception handling (the current proposal), for C++ exceptions and
      `setjmp`/`longjmp` built with `-mllvm -wasm-use-legacy-eh=false`;
      the legacy encoding fails validation cleanly. (#61)

Left for after 0.1.0, by the same review: linking instances to each
other, tables and function references from R, SIMD, and interpreter
speed switches (`musttail`, jump cache).

**Exit:** all three merged with every check green.

---

## 3. Release checklist (0.1.0)

- [ ] All must-have boxes in M0–M7 are ticked.
- [ ] The exported functions match §1 exactly. No extra exports, and every
      one is documented.
- [ ] `devtools::check()` 0/0/0 locally, and the r-actions `R-CMD-check`
      full profile green: macOS, Windows and Linux runners (release and
      oldrel) plus the CRAN-like clang23, ubuntu-clang and gcc16 containers.
      These replace win-builder and mac-builder.
- [ ] r-actions `native-checks` green: ASan/UBSan (gcc and clang),
      valgrind, rchk, gctorture, LTO, `-fanalyzer`, and CRAN special checks.
- [ ] `tools/spec/run.sh` and `tools/build-fixtures.sh` run locally with no
      new failures and no diff.
- [x] The `cran-extrachecks` skill has been run and its findings addressed.
- [ ] Tarball under 5 MB, and check time on CRAN-like machines under 5 minutes.
- [x] `cran-comments.md` written: first submission, vendored toywasm credited,
      no system requirements.
- [ ] `usethis::use_version("minor")` → 0.1.0 (from 0.0.0.9000), commit, submit, and
      tag `v0.1.0` once CRAN accepts it. Then bump to 0.1.0.9000. The 0.1.0 site
      then builds at the root, with the dev site in `dev/`.

---

## 4. After 0.1.0

A short list, ordered by expected demand. Each item needs a design note in
`design.md` before work starts.

1. Opt-in WASI subset in R (design §10). This is the most likely user request.
2. SIMD, then exception handling (toywasm config flags, size check).
3. Lossless i64 via `bit64` (Suggests).
4. Re-entrant callbacks; linking instances to each other.
5. `wasm_with_buffer()` allocator helper.
6. Performance pass and benchmarks; re-vendor toywasm each quarter.
