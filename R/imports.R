#' Give a module an R function as an import
#'
#' `wasm_func()` wraps an R function so a module can import it. Pass it to
#' [wasm_instantiate()] in `imports`, a list of lists named by the module's
#' import module and field names:
#'
#' ```r
#' imports = list(env = list(log_i32 = wasm_func(function(x) message(x), "i32")))
#' ```
#'
#' When the WebAssembly code calls the import, the R function receives the
#' arguments converted as described in [wasm_instantiate()], and its return
#' value is converted back and checked against `results`: nothing is
#' expected when `results` is empty, a single value when it has one type, and
#' a list of values when it has several.
#'
#' If the R function has a parameter named `caller`, it also receives a
#' `nanowasm_caller`, whose `memory()` returns the calling instance's memory
#' (see [wasm_memory()]). This is how an import reads a string or buffer the
#' module passes by pointer. The caller is only valid during the call.
#'
#' An error in the R function stops the WebAssembly call, which signals a
#' `nanowasm_host_error`. Its `parent` field holds the original condition.
#' An interrupt or other jump out of the R function unwinds the WebAssembly
#' call too, and the instance remains usable. An instance runs one call at a
#' time, so an import cannot call back into its own instance: that signals a
#' `nanowasm_reentry_error`.
#'
#' @param fn An R function.
#' @param params,results Character vectors of WebAssembly value types:
#'   `"i32"`, `"i64"`, `"f32"` or `"f64"`.
#' @return A `nanowasm_func`.
#' @export
#' @examples
#' mod <- wasm_module(system.file("extdata", "log.wasm", package = "nanowasm"))
#' wasm_imports(mod)
#'
#' log_str <- function(ptr, len, caller) {
#'   msg <- wasm_read_string(caller$memory(), ptr, len)
#'   message("module says: ", msg)
#' }
#' inst <- wasm_instantiate(mod, imports = list(
#'   env = list(log = wasm_func(log_str, params = c("i32", "i32")))
#' ))
#' inst$greet()
wasm_func <- function(fn, params = character(), results = character()) {
  call <- sys.call()
  if (!is.function(fn)) {
    nanowasm_abort("nanowasm_argument_error", "`fn` must be a function.", call = call)
  }
  check_valtypes(params, "params", call)
  check_valtypes(results, "results", call)
  structure(
    list(
      fn = fn,
      params = params,
      results = results,
      has_caller = "caller" %in% names(formals(args(fn)))
    ),
    class = "nanowasm_func"
  )
}

valtypes <- c("i32", "i64", "f32", "f64")

check_valtypes <- function(x, arg, call) {
  if (!is.character(x) || anyNA(x) || !all(x %in% valtypes)) {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0(
        "`", arg, "` must be a character vector of WebAssembly types: ",
        paste0("\"", valtypes, "\"", collapse = ", "), "."
      ),
      call = call
    )
  }
}

# "(i32, i32) -> i32", as the C side formats function types.
format_signature <- function(params, results) {
  paste0(
    "(", paste(params, collapse = ", "), ") -> ",
    if (length(results) == 1) results else paste0("(", paste(results, collapse = ", "), ")")
  )
}

#' @export
format.nanowasm_func <- function(x, ...) {
  paste0("<nanowasm_func> ", format_signature(x$params, x$results))
}

#' @export
print.nanowasm_func <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}

# Match `imports` against the module's imports. Returns the R wrapper for
# each import, in module order, or signals one nanowasm_link_error that
# lists every problem.
link_imports <- function(module, imports, call) {
  needed <- module$imports
  if (!is.list(imports) || (length(imports) > 0 && is.null(names(imports)))) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "`imports` must be a named list of named lists of `wasm_func()`s.",
      call = call
    )
  }
  if (nrow(needed) == 0) {
    return(list())
  }
  keys <- paste0(needed$module, ".", needed$name)
  given <- lapply(seq_len(nrow(needed)), function(i) {
    group <- imports[[needed$module[[i]]]]
    if (is.list(group) && !is.null(names(group))) group[[needed$name[[i]]]]
  })

  bad <- !vapply(given, function(f) is.null(f) || inherits(f, "nanowasm_func"), TRUE)
  if (any(bad)) {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0(
        "Imports must be created with `wasm_func()`; ",
        paste0("`", keys[bad], "`", collapse = ", "), " is not."
      ),
      call = call
    )
  }

  missing <- vapply(given, is.null, TRUE)
  unsupported <- needed$kind != "function"
  given_type <- vapply(given, function(f) {
    if (is.null(f)) NA_character_ else format_signature(f$params, f$results)
  }, "")
  mismatch <- !missing & !unsupported & given_type != needed$type

  problems <- c(
    if (any(unsupported)) paste0(
      "- ", paste0("`", keys[unsupported], "`", collapse = ", "),
      ": importing ",
      paste(plural_kind(unique(needed$kind[unsupported])), collapse = ", "),
      " is not supported; only functions can be imported."
    ),
    if (any(missing & !unsupported)) paste0(
      "- missing: ", paste0("`", keys[missing & !unsupported], "`", collapse = ", "), "."
    ),
    if (any(mismatch)) paste0(
      "- `", keys[mismatch], "` has type ", needed$type[mismatch],
      " but the R function was declared as ", given_type[mismatch], "."
    )
  )
  if (length(problems) > 0) {
    nanowasm_abort(
      "nanowasm_link_error",
      paste0("Can't link the module's imports:\n", paste(problems, collapse = "\n")),
      missing = needed[missing & !unsupported, , drop = FALSE],
      mismatch = data.frame(
        import = keys[mismatch],
        expected = needed$type[mismatch],
        given = given_type[mismatch],
        stringsAsFactors = FALSE
      ),
      call = call
    )
  }

  Map(host_wrapper, given, keys, MoreArgs = list(module = module))
}

plural_kind <- function(kind) {
  c(memory = "memories", table = "tables", global = "globals")[kind]
}

# The closure the C trampoline calls as wrapper(args, self): it returns
# list(TRUE, value), or list(FALSE, condition, message) if `fn` signalled an
# error. Errors must come back as values; see src/nw_host.c.
host_wrapper <- function(f, key, module) {
  fn <- f$fn
  has_caller <- f$has_caller
  wrapper <- function(args, self) {
    tryCatch(
      {
        if (has_caller) {
          caller <- new_caller(self, module)
          on.exit(invalidate_caller(caller), add = TRUE)
          args <- c(args, list(caller = caller))
        }
        list(TRUE, do.call(fn, args))
      },
      error = function(e) {
        list(
          FALSE, e,
          paste0("The R function imported as `", key, "` failed: ", conditionMessage(e))
        )
      }
    )
  }
  # Internal: WASI functions take i64 arguments beyond 2^53 as rounded
  # doubles rather than failing (see src/nw_host.c).
  if (isTRUE(f$lossy_i64)) attr(wrapper, "nanowasm_lossy_i64") <- TRUE
  wrapper
}

new_caller <- function(self, module) {
  state <- new.env(parent = emptyenv())
  state$active <- TRUE
  instance <- structure(
    list(ptr = self, module = module, limits = NULL),
    class = "nanowasm_instance"
  )
  structure(
    list(
      memory = function(name = NULL) {
        if (!state$active) {
          nanowasm_abort(
            "nanowasm_argument_error",
            "This caller is no longer valid: it can only be used during the host call.",
            call = sys.call()
          )
        }
        wasm_memory(instance, name)
      },
      state = state
    ),
    class = "nanowasm_caller"
  )
}

invalidate_caller <- function(caller) {
  caller$state$active <- FALSE
}

#' @export
format.nanowasm_caller <- function(x, ...) {
  paste0("<nanowasm_caller>", if (!x$state$active) " (no longer valid)")
}

#' @export
print.nanowasm_caller <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}
