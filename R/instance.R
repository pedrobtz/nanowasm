#' Instantiate a module and call its functions
#'
#' `wasm_instantiate()` creates an instance of a module: it allocates the
#' module's memories, tables and globals, initialises them, and runs the
#' module's start function if it has one. `wasm_call()` calls one of the
#' instance's exported functions. `inst$name(...)` is shorthand for
#' `wasm_call(inst, "name", ...)`.
#'
#' Calls are scalar: each argument is one value, matched to the function's
#' parameter types.
#'
#' * `i32` accepts an integer, or a double holding a whole number in
#'   \eqn{[-2^{31}, 2^{32})}; values from \eqn{2^{31}} up are taken as the
#'   unsigned bit pattern. `i32` results are integers. `NA_integer_` shares
#'   its bits with \eqn{-2^{31}}, so the two are the same value in
#'   WebAssembly.
#' * `i64` accepts a whole number with magnitude at most \eqn{2^{53}}, and
#'   `i64` results are doubles. A result that a double cannot represent
#'   exactly signals a `nanowasm_precision_error` rather than being rounded.
#' * `f32` and `f64` accept numbers, and return doubles.
#'
#' A function with no results returns `NULL` invisibly, one with a single
#' result returns it as a length-one vector, and one with several results
#' returns an unnamed list.
#'
#' If the WebAssembly code traps, the call signals a `nanowasm_trap` (see
#' [nanowasm-conditions]). Every call runs under the instance's
#' [wasm_limits()], so runaway recursion, memory growth or loops end in an
#' error rather than exhausting the R session. Ctrl-C interrupts a running
#' call.
#'
#' An instance runs one call at a time.
#'
#' @param module A `nanowasm_module` from [wasm_module()].
#' @param limits Resource limits from [wasm_limits()]. The default is
#'   `getOption("nanowasm.limits")`, or `wasm_limits()` if that is unset.
#' @param instance A `nanowasm_instance` from `wasm_instantiate()`.
#' @param name The name of an exported function.
#' @param ... The function's arguments, in order.
#' @return `wasm_instantiate()` returns a `nanowasm_instance`. `wasm_call()`
#'   returns the function's results as described above.
#' @export
#' @examples
#' mod <- wasm_module(system.file("extdata", "fib.wasm", package = "nanowasm"))
#' inst <- wasm_instantiate(mod)
#' inst$fib(20L)
#' wasm_call(inst, "fib", 10L)
wasm_instantiate <- function(module, limits = NULL) {
  call <- sys.call()
  if (is.null(limits)) limits <- default_limits()
  if (!inherits(limits, "nanowasm_limits")) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "`limits` must be created by `wasm_limits()`.",
      call = call
    )
  }
  if (!inherits(module, "nanowasm_module")) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "`module` must be a nanowasm module from `wasm_module()`.",
      call = call
    )
  }
  ptr <- nw_ptr(module, call)
  imports <- module$imports
  if (nrow(imports) > 0) {
    nanowasm_abort(
      "nanowasm_link_error",
      paste0(
        "The module needs ", nrow(imports), " import",
        if (nrow(imports) > 1) "s", ", but none were given: ",
        paste0("`", imports$module, ".", imports$name, "`", collapse = ", "),
        ". Imports are not supported yet."
      ),
      missing = imports,
      call = call
    )
  }
  inst <- nw_check(.Call(nw_instantiate, ptr, unclass(limits)), call)
  structure(
    list(ptr = inst, module = module, limits = limits),
    class = "nanowasm_instance"
  )
}

#' @rdname wasm_instantiate
#' @export
wasm_call <- function(instance, name, ...) {
  nw_call_impl(instance, name, list(...), sys.call())
}

nw_call_impl <- function(instance, name, args, call) {
  check_instance(instance, call)
  check_string(name, "name", call)
  ptr <- nw_ptr(instance, call)
  res <- nw_check(.Call(nw_call, ptr, name, args), call)
  if (is.null(res)) invisible() else res
}

#' @export
`$.nanowasm_instance` <- function(x, name) {
  call <- sys.call()
  call[[1]] <- as.name("$")
  export_function(x, name, call)
}

#' @export
`[[.nanowasm_instance` <- function(x, i, ...) {
  call <- sys.call()
  call[[1]] <- as.name("[[")
  export_function(x, i, call)
}

export_function <- function(x, name, call) {
  exports <- .subset2(x, "module")$exports
  kind <- exports$kind[match(name, exports$name)]
  if (is.na(kind)) {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0("The instance has no export named `", name, "`."),
      call = call
    )
  }
  if (kind != "function") {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0("The export `", name, "` is a ", kind, ", not a function."),
      call = call
    )
  }
  force(x)
  function(...) nw_call_impl(x, name, list(...), sys.call())
}

#' @export
`$<-.nanowasm_instance` <- function(x, name, value) {
  nanowasm_abort(
    "nanowasm_argument_error",
    "The exports of a nanowasm instance cannot be modified.",
    call = sys.call()
  )
}

#' @export
`[[<-.nanowasm_instance` <- `$<-.nanowasm_instance`

#' @export
names.nanowasm_instance <- function(x) {
  .subset2(x, "module")$exports$name
}

#' @export
format.nanowasm_instance <- function(x, ...) {
  c("<nanowasm_instance>", format_externs("exports", .subset2(x, "module")$exports))
}

#' @export
print.nanowasm_instance <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}

check_instance <- function(x, call) {
  if (!inherits(x, "nanowasm_instance")) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "`instance` must be a nanowasm instance from `wasm_instantiate()`.",
      call = call
    )
  }
  invisible(x)
}

#' Read and write an instance's exported globals
#'
#' `wasm_global()` returns the current value of an exported global, converted
#' as described in [wasm_instantiate()]. `wasm_global<-` sets a mutable one;
#' setting an immutable global is an error.
#'
#' @param instance A `nanowasm_instance`.
#' @param name The export name of the global.
#' @param value The new value.
#' @return `wasm_global()` returns the value. `wasm_global<-` returns the
#'   instance, whose global has been changed in place.
#' @export
#' @examples
#' mod <- wasm_module(system.file("extdata", "sum.wasm", package = "nanowasm"))
#' inst <- wasm_instantiate(mod)
#' wasm_global(inst, "heap_top")
#' inst$alloc(64L)
#' wasm_global(inst, "heap_top")
#' wasm_global(inst, "heap_top") <- 4096L
#' inst$alloc(8L)
wasm_global <- function(instance, name) {
  call <- sys.call()
  check_instance(instance, call)
  check_string(name, "name", call)
  nw_check(.Call(nw_global_get, nw_ptr(instance, call), name), call)
}

#' @rdname wasm_global
#' @export
`wasm_global<-` <- function(instance, name, value) {
  call <- sys.call()
  check_instance(instance, call)
  check_string(name, "name", call)
  nw_check(.Call(nw_global_set, nw_ptr(instance, call), name, value), call)
  instance
}
