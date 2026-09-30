/*
 * Build configuration for the vendored toywasm (src/toywasm/).
 *
 * Upstream generates this file from lib/toywasm_config.h.in with CMake.
 * nanowasm ships no configure step, so the choices are fixed here by hand.
 * Every upstream option is listed; the ones left undefined are off.
 * Changing a feature flag may need more upstream files: see
 * tools/vendor/toywasm-files.txt.
 */
#if !defined(_TOYWASM_CONFIG_H)
#define _TOYWASM_CONFIG_H

/* Interpreter implementation: upstream defaults. */
#define TOYWASM_USE_SEPARATE_EXECUTE
/* #undef TOYWASM_USE_SEPARATE_VALIDATE */
#define TOYWASM_PROCESS_INSN_WITH_SWITCH
/* Off: relies on clang's musttail and is only a speed-up. */
/* #undef TOYWASM_USE_TAILCALL */
/* #undef TOYWASM_FORCE_USE_TAILCALL */
/* #undef TOYWASM_USE_SIMD */
/* Off: needs -fshort-enums, which changes the ABI of every enum. */
/* #undef TOYWASM_USE_SHORT_ENUMS */
/* Off: only needed for threads without host pthreads. */
/* #undef TOYWASM_USE_USER_SCHED */
/* #undef TOYWASM_ENABLE_TRACING */
/* #undef TOYWASM_ENABLE_TRACING_INSN */
#define TOYWASM_SORT_EXPORTS
#define TOYWASM_USE_JUMP_BINARY_SEARCH
/* #undef TOYWASM_USE_JUMP_CACHE */
#define TOYWASM_JUMP_CACHE2_SIZE 4
#define TOYWASM_USE_LOCALS_FAST_PATH
#define TOYWASM_USE_LOCALS_CACHE
#define TOYWASM_USE_SEPARATE_LOCALS
#define TOYWASM_USE_SMALL_CELLS
#define TOYWASM_USE_RESULTTYPE_CELLIDX
#define TOYWASM_USE_LOCALTYPE_CELLIDX
/* #undef TOYWASM_PREALLOC_SHARED_MEMORY */

/* On: the per-instance memory limit is enforced through heap tracking. */
#define TOYWASM_ENABLE_HEAP_TRACKING
/* #undef TOYWASM_ENABLE_HEAP_TRACKING_PEAK */

/* Off: nanowasm never re-encodes modules. */
/* #undef TOYWASM_ENABLE_WRITER */
/* #undef TOYWASM_MAINTAIN_EXPR_END */

/* WebAssembly proposals. SIMD and exception handling are planned for after
   0.1.0; threads, WASI and dynamic linking are out of scope. */
/* #undef TOYWASM_ENABLE_WASM_SIMD */
/* #undef TOYWASM_ENABLE_WASM_EXCEPTION_HANDLING */
#define TOYWASM_EXCEPTION_MAX_CELLS 4
#define TOYWASM_ENABLE_WASM_EXTENDED_CONST
#define TOYWASM_ENABLE_WASM_MULTI_MEMORY
#define TOYWASM_ENABLE_WASM_TAILCALL
/* #undef TOYWASM_ENABLE_WASM_THREADS */
/* #undef TOYWASM_ENABLE_WASM_CUSTOM_PAGE_SIZES */
#define TOYWASM_ENABLE_WASM_NAME_SECTION
/* #undef TOYWASM_ENABLE_WASI */
/* #undef TOYWASM_ENABLE_WASI_THREADS */
/* #undef TOYWASM_ENABLE_WASI_LITTLEFS */
/* #undef TOYWASM_ENABLE_LITTLEFS_STATS */
/* #undef TOYWASM_ENABLE_DYLD */
/* #undef TOYWASM_ENABLE_DYLD_DLFCN */

#endif /* !defined(_TOYWASM_CONFIG_H) */
