#' Resource limits for an instance
#'
#' `wasm_limits()` describes how much an instance may consume. Pass it to
#' [wasm_instantiate()], or set `options(nanowasm.limits = wasm_limits(...))`
#' to change the default for every instance.
#'
#' * `memory` caps everything the interpreter allocates for the instance:
#'   its linear memories, tables, globals and the stacks of running calls.
#'   A `memory.grow` that would exceed it fails inside WebAssembly (returning
#'   -1, as the specification requires). Any other allocation that would
#'   exceed it signals a `nanowasm_memory_limit` error.
#' * `frames` is the maximum call depth, and `stack` the maximum number of
#'   value-stack cells (4 bytes each). Exceeding either signals a
#'   `nanowasm_stack_exhausted` error.
#' * `timeout` is the wall-clock time a single call (including the start
#'   function at instantiation) may run, in seconds. Exceeding it signals a
#'   `nanowasm_timeout` error. It is checked about every 50 milliseconds of
#'   execution.
#'
#' Pressing Ctrl-C (or Esc) interrupts a running call regardless of the
#' limits, as it does for R code.
#'
#' A call stopped by a limit or an interrupt may leave the instance's memory
#' and globals partly updated. The instance stays usable, but whether its
#' state still makes sense depends on the module.
#'
#' @param memory Maximum bytes, or `Inf`.
#' @param frames Maximum call depth.
#' @param stack Maximum value-stack cells.
#' @param timeout Maximum seconds per call, or `Inf`.
#' @return A `nanowasm_limits` object.
#' @export
#' @examples
#' wasm_limits()
#' wasm_limits(memory = 16 * 2^20, timeout = 1)
#'
#' mod <- wasm_module(system.file("extdata", "fib.wasm", package = "nanowasm"))
#' inst <- wasm_instantiate(mod, limits = wasm_limits(timeout = 0.5))
#' try(inst$fib(40L))
wasm_limits <- function(memory = 256 * 2^20, frames = 10000, stack = 1e6,
                        timeout = Inf) {
  call <- sys.call()
  structure(
    list(
      memory = check_limit(memory, "memory", call, allow_inf = TRUE),
      frames = check_limit(frames, "frames", call, whole = TRUE),
      stack = check_limit(stack, "stack", call, whole = TRUE),
      timeout = check_limit(timeout, "timeout", call, allow_inf = TRUE, whole = FALSE)
    ),
    class = "nanowasm_limits"
  )
}

check_limit <- function(x, arg, call, allow_inf = FALSE, whole = TRUE) {
  ok <- is.numeric(x) && length(x) == 1 && !is.na(x) && x > 0 &&
    (allow_inf || is.finite(x)) &&
    (!whole || !is.finite(x) || x == floor(x))
  if (!ok) {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0(
        "`", arg, "` must be a single positive ",
        if (whole) "whole " else "", "number",
        if (allow_inf) " or `Inf`" else "", "."
      ),
      call = call
    )
  }
  as.double(x)
}

default_limits <- function() {
  limits <- getOption("nanowasm.limits")
  if (is.null(limits)) wasm_limits() else limits
}

#' @export
format.nanowasm_limits <- function(x, ...) {
  mem <- if (is.finite(x$memory)) format_bytes(x$memory) else "unlimited"
  timeout <- if (is.finite(x$timeout)) paste(x$timeout, "s") else "none"
  c(
    "<nanowasm_limits>",
    paste0("  memory:  ", mem),
    paste0("  frames:  ", format(x$frames, big.mark = ",", scientific = FALSE)),
    paste0("  stack:   ", format(x$stack, big.mark = ",", scientific = FALSE), " cells"),
    paste0("  timeout: ", timeout)
  )
}

#' @export
print.nanowasm_limits <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}

format_bytes <- function(x) {
  units <- c("bytes", "KiB", "MiB", "GiB", "TiB")
  i <- if (x < 1) 1 else max(1, min(length(units), floor(log(x, 1024)) + 1))
  paste(format(x / 1024^(i - 1), digits = 3), units[i])
}
