#' Resource usage of an instance
#'
#' `wasm_stats()` reports what an instance has consumed so far:
#'
#' * `memory`: bytes the interpreter currently holds for the instance (its
#'   linear memories, tables, globals and other internal state), the
#'   quantity that [wasm_limits()]' `memory` limit applies to;
#'   `memory_peak`, the most it has held at once; and `memory_limit`.
#' * `runs`: how many times WebAssembly code has run in the instance: calls
#'   from R (including through `$`), plus the start function.
#' * `calls`: WebAssembly functions called during those runs, counting
#'   `host_calls`, the calls to imported functions (R functions and WASI).
#' * `branches`: branch instructions taken, a rough measure of how much work
#'   the code did.
#'
#' Counts are cumulative over the instance's life. Linear memory is
#' allocated as the module touches it, so `memory` can be well below the
#' memory's declared size.
#'
#' @param instance A `nanowasm_instance`.
#' @return A `nanowasm_stats` object: a list of numbers (bytes and counts),
#'   with a print method.
#' @export
#' @examples
#' mod <- wasm_module(system.file("extdata", "fib.wasm", package = "nanowasm"))
#' inst <- wasm_instantiate(mod)
#' inst$fib(20L)
#' wasm_stats(inst)
#'
#' # fib(n) makes 2 * fib(n + 1) - 1 calls.
#' before <- wasm_stats(inst)$calls
#' inst$fib(10L)
#' wasm_stats(inst)$calls - before
wasm_stats <- function(instance) {
  call <- sys.call()
  check_instance(instance, call)
  stats <- .Call(nw_stats, nw_ptr(instance, call))
  structure(as.list(stats), class = "nanowasm_stats")
}

#' @export
format.nanowasm_stats <- function(x, ...) {
  count <- function(v) format(v, big.mark = ",", scientific = FALSE)
  limit <- if (is.finite(x$memory_limit)) format_bytes(x$memory_limit) else "none"
  c(
    "<nanowasm_stats>",
    paste0("  memory:     ", format_bytes(x$memory), " (peak ", format_bytes(x$memory_peak), ", limit ", limit, ")"),
    paste0("  runs:       ", count(x$runs)),
    paste0("  calls:      ", count(x$calls), " (", count(x$host_calls), " to imports)"),
    paste0("  branches:   ", count(x$branches))
  )
}

#' @export
print.nanowasm_stats <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}
