#' Conditions signalled by nanowasm
#'
#' Every error nanowasm raises has class `nanowasm_error`, plus a more
#' specific class that code can catch with [tryCatch()]:
#'
#' * `nanowasm_invalid_object`: the object no longer points at a live module
#'   or instance, for example after a [saveRDS()] / [readRDS()] round trip.
#' * `nanowasm_validation_error`: the bytes are not a valid WebAssembly
#'   module.
#' * `nanowasm_link_error`: the module cannot be instantiated with the
#'   imports given. The `missing` field lists missing imports.
#' * `nanowasm_argument_error`: a value passed from R does not fit the
#'   function's signature. Its subclass `nanowasm_precision_error` is used when
#'   an `i64` result cannot be represented exactly as a double.
#' * `nanowasm_unsupported`: the function uses a type nanowasm cannot pass
#'   between R and WebAssembly (`funcref`, `externref`, `v128`).
#' * `nanowasm_trap`: the WebAssembly code trapped. `trap_id` names the trap
#'   (`"div_by_zero"`, `"unreachable"`, `"out_of_bounds_memory_access"`, ...)
#'   and `detail` holds the interpreter's own message. Subclasses:
#'   `nanowasm_stack_exhausted` (call or value stack limit) and
#'   `nanowasm_out_of_bounds` (memory or table access out of bounds).
#'
#'   A trap also says where it happened: `func` is the name of the function
#'   that trapped, `backtrace` the names of the functions on the call stack,
#'   innermost first (at most 64), and `depth` the full depth of the stack.
#'   Names come from the module's name section (wat2wasm's `--debug-names`,
#'   or a compiler's debug information), else from its exports and
#'   imports, else they are `func[N]`. Timeouts and errors in imported R
#'   functions carry the same fields.
#' * `nanowasm_memory_limit`: the instance reached its memory limit (see
#'   [wasm_limits()]), or the interpreter could not allocate memory.
#' * `nanowasm_timeout`: a call ran longer than its time limit. `elapsed` and
#'   `limit` are in seconds.
#' * `nanowasm_reentry_error`: an instance was called while already running a
#'   call.
#' * `nanowasm_runtime_error`: any other failure inside the interpreter.
#'
#' Out-of-bounds [wasm_read()] and [wasm_write()] calls signal
#' `nanowasm_out_of_bounds` too, as a subclass of `nanowasm_argument_error`.
#'
#' Pressing Ctrl-C during a call signals R's usual `interrupt` condition.
#'
#' A WASI program that calls `exit()` stops its WebAssembly call with a
#' `nanowasm_host_error` whose `parent` has class `nanowasm_wasi_exit` and an
#' exit `status`; [wasm_wasi_start()] and [wasm_run()] turn it into the
#' returned status.
#'
#' @name nanowasm-conditions
#' @examples
#' mod <- wasm_module(system.file("extdata", "add.wasm", package = "nanowasm"))
#' inst <- wasm_instantiate(mod)
#' tryCatch(
#'   inst$add(1L),
#'   nanowasm_argument_error = function(e) conditionMessage(e)
#' )
NULL

nanowasm_abort <- function(class, message, ..., call = NULL) {
  cnd <- structure(
    c(list(message = message, call = call), list(...)),
    class = c(class, "nanowasm_error", "error", "condition")
  )
  stop(cnd)
}

# Signal a failure returned by the C layer (see src/nw_failure.c), or pass
# any other result through.
nw_check <- function(res, call = NULL) {
  if (inherits(res, "nanowasm_failure")) {
    if (identical(res$class, "nanowasm_interrupt")) {
      nw_interrupt()
    }
    # Not do.call(): it would evaluate `call`, re-running the failed call.
    cnd <- structure(
      c(list(message = res$message, call = call), res$fields),
      class = c(res$class, "nanowasm_error", "error", "condition")
    )
    stop(cnd)
  }
  res
}

# A Ctrl-C arrived during a WebAssembly call. It was consumed while checking
# for it, so re-signal it the way R does for R code: an `interrupt` condition
# for handlers, then a jump back to the top level.
nw_interrupt <- function() {
  cnd <- structure(
    list(message = "", call = NULL),
    class = c("interrupt", "condition")
  )
  signalCondition(cnd)
  invokeRestart("abort")
}

# The external pointer inside a nanowasm object, checked to be live.
nw_ptr <- function(x, call = NULL) {
  ptr <- .subset2(x, "ptr")
  if (!.Call(nw_ptr_is_live, ptr)) {
    what <- sub("^nanowasm_", "", class(x)[[1]])
    nanowasm_abort(
      "nanowasm_invalid_object",
      paste0(
        "This ", what, " is no longer valid. WebAssembly objects cannot be ",
        "saved and restored; create it again."
      ),
      call = call
    )
  }
  ptr
}
