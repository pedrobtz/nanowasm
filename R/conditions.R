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
#' * `nanowasm_memory_limit`: the interpreter could not allocate memory.
#' * `nanowasm_runtime_error`: any other failure inside the interpreter.
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
    # Not do.call(): it would evaluate `call`, re-running the failed call.
    cnd <- structure(
      c(list(message = res$message, call = call), res$fields),
      class = c(res$class, "nanowasm_error", "error", "condition")
    )
    stop(cnd)
  }
  res
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
