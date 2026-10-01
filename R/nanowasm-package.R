#' @description
#' Load WebAssembly modules and call their functions from R, using the
#' bundled toywasm interpreter. Start with `vignette("nanowasm")`.
#'
#' * [wasm_module()] loads a module; [wasm_exports()] and [wasm_imports()]
#'   describe it.
#' * [wasm_instantiate()] creates an instance, whose exported functions are
#'   called with `inst$name(...)` or [wasm_call()].
#' * [wasm_memory()] and [wasm_read()] / [wasm_write()] move data through
#'   linear memory, and [wasm_global()] reads and sets globals.
#' * [wasm_func()] turns an R function into an import.
#' * [wasm_run()] and [wasm_wasi()] run WASI programs, with only the
#'   arguments, environment and directories you grant.
#' * [wasm_limits()] bounds memory, recursion and time, and
#'   [nanowasm-conditions] lists the errors nanowasm signals.
#'
#' @section Options:
#' * `nanowasm.limits`: the default [wasm_limits()] for new instances.
#' * `nanowasm.max_module_size`: the largest module, in bytes, that
#'   [wasm_module()] accepts (64 MB by default).
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @useDynLib nanowasm, .registration = TRUE
## usethis namespace: end
NULL
