# nanowasm roadmap to 0.1.0

Companion to [design.md](design.md). This file plans the first release,
**nanowasm 0.1.0 on CRAN**. Work after the release is only listed briefly at
the end.

How to use this file:

- Milestones run in order. Each one ends in a mergeable state with CI green
  (quick profile on every PR; add the `full-ci` label to the PR that closes
  a milestone).
- Each task is a GitHub issue under its milestone. PRs close them with
  `Closes #n`, and the same PR ticks the box here. Add user-facing changes to
  `NEWS.md` under the development heading.
- When a milestone closes, bump the dev version (`usethis::use_version("dev")`:
  0.0.0.9001, .9002, …) so every installed build can be identified.
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
| Conditions | the full class tree in design §8 |
| Wasm features | MVP + bulk memory, reference types (inside the module only), multi-value, tail calls, extended const, multi-memory, name section |
| Platforms | Linux, macOS, Windows (Rtools), R ≥ 4.3 |

### Out of scope (explicitly deferred)

WASI (any subset), SIMD, exception handling, threads/shared memory,
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
- [x] Sources pruned to 33 `.c` / 56 `.h`, with no stubs needed. (#8)
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

- [ ] Fixture pipeline: `.wat` + committed `.wasm`, `tools/build-fixtures.sh`,
      and a CI job that verifies the committed binaries match their sources.
- [ ] `wasm_module()` / `wasm_validate()` (keeps the bytes alive, module size limit).
- [ ] `wasm_exports()` / `wasm_imports()` / `print` / signature formatting.
- [ ] `wasm_instantiate()` without imports (error if the module needs any)
      and the start function.
- [ ] `wasm_call()`, `$`, `names()`, and value mapping with edge-case tests.
- [ ] Condition machinery (C returns error data, `nanowasm_abort()` signals it):
      validation, argument/precision, trap + `trap_id` table, invalid object.
- [ ] Finalisers and lifetime tests (`gc()` torture, `saveRDS` round trip).
- [ ] `inst/extdata/add.wasm`, `fib.wasm`, and roxygen examples.

**Exit:** `inst$fib(25L)` works. Every trap fixture maps to the right class.
Coverage of `R/` is ≥ 90%.

### M3: Memory and limits (0.0.0.9004)

Tracked in [milestone M3](https://github.com/pedrobtz/nanowasm/milestone/4) (issues #23–#28).

- [ ] Memory API (design §4.4): all element types, bounds-checked,
      endian-safe, strings.
- [ ] `wasm_global()` get/set.
- [ ] `wasm_limits()` + option: per-instance `mem_context` limit and
      `exec_options`.
- [ ] Interrupt hook patch. Timeout → `nanowasm_timeout`, Ctrl-C → `interrupt`.
- [ ] Classes `nanowasm_stack_exhausted`, `nanowasm_memory_limit`,
      `nanowasm_out_of_bounds`.
- [ ] Hostile fixtures: infinite loop, unbounded recursion, `memory.grow`
      bomb, huge table. Each fails fast with the right class and leaves R usable.
- [ ] Example: sum a numeric vector through memory, using the module's own
      `alloc`.

**Exit:** no fixture can crash, hang or exhaust the memory of the R session.
Ctrl-C has been checked by hand on all three OSes.

### M4: Host functions (0.0.0.9005)

Tracked in [milestone M4](https://github.com/pedrobtz/nanowasm/milestone/5) (issues #29–#34).

- [ ] `wasm_func()` and the `imports` list. Link errors report every missing
      import at once and show mismatched signatures side by side.
- [ ] Trampoline + per-import binding (design §6.2).
- [ ] Safe R evaluation: `tryCatch` + `R_UnwindProtect` / `R_ContinueUnwind`
      (design §6.3).
- [ ] `nanowasm_host_error` with `$parent`, and checks on return values.
- [ ] `caller` → `nanowasm_caller$memory()`, invalidated after the host call
      returns.
- [ ] Re-entry → clear error.
- [ ] Tests: callbacks that error, warn, get interrupted, exit through a
      restart, return bad values or re-enter. Also a `gc()` inside a callback.
- [ ] Example: a string-logging module using an imported `log(ptr, len)`.

**Exit:** every non-local exit from a callback leaves the instance usable.
Clean under ASan.

### M5: Release hardening (0.0.0.9006 → 0.1.0)

Tracked in [milestone M5](https://github.com/pedrobtz/nanowasm/milestone/6) (issues #35–#42).

Must-have:

- [ ] Sanitizer CI (ASan + UBSan) and valgrind on the full profile, both clean.
- [ ] Fuzz smoke test: mutated fixtures fed to `wasm_module()` /
      `wasm_instantiate()` for a bounded time in CI. It must never crash.
- [ ] Getting-started vignette: load → call → memory → host function →
      limits and conditions.
- [ ] Documentation on every export, with runnable examples (no `\dontrun`),
      a pkgdown reference grouped by area, and a README example matching
      the vignette.
- [ ] A section on what the sandbox guarantees and what it does not.
- [ ] `NEWS.md` entry for 0.1.0.

Should-have (drop if it holds the release back more than a week):

- [ ] Spec-test subset runner in `tools/` (CI only), with the pass rate and
      known gaps recorded.
- [ ] Interrupt hook and xlog patches offered to toywasm.

**Exit:** see §3.

---

## 3. Release checklist (0.1.0)

- [ ] All must-have boxes in M0–M5 are ticked.
- [ ] The exported functions match §1 exactly. No extra exports, and every
      one is documented.
- [ ] `devtools::check()` 0/0/0 locally. `R CMD check --as-cran` clean on
      win-builder (release + devel), mac-builder, and rhub (clang-UBSAN,
      valgrind).
- [ ] The `cran-extrachecks` skill has been run and its findings addressed.
- [ ] Tarball under 5 MB, and check time on CRAN-like machines under 5 minutes.
- [ ] `cran-comments.md` written: first submission, vendored toywasm credited,
      no system requirements.
- [ ] `usethis::use_version("minor")` → 0.1.0, commit, submit, and tag
      `v0.1.0` once CRAN accepts it. Then bump to 0.1.0.9000.

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
