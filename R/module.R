#' Load a WebAssembly module
#'
#' `wasm_module()` decodes and validates a WebAssembly binary. The result can
#' be instantiated any number of times with [wasm_instantiate()].
#' `wasm_validate()` only checks that `x` is a valid module.
#'
#' A module cannot be saved with [saveRDS()]: the restored object is no longer
#' valid and using it signals a `nanowasm_invalid_object` error.
#'
#' @param x A raw vector holding a WebAssembly binary, or the path to a
#'   `.wasm` file.
#' @return `wasm_module()` returns a `nanowasm_module` object.
#'   `wasm_validate()` returns `TRUE` invisibly, or signals a
#'   `nanowasm_validation_error`.
#' @seealso [wasm_exports()] to list what a module provides and needs.
#' @export
#' @examples
#' path <- system.file("extdata", "add.wasm", package = "nanowasm")
#' mod <- wasm_module(path)
#' mod
#'
#' wasm_validate(path)
#' try(wasm_validate(as.raw(1:8)))
wasm_module <- function(x) {
  call <- sys.call()
  bytes <- module_bytes(x, call)
  ptr <- nw_check(.Call(nw_module_load, bytes), call)
  new_module(ptr, length(bytes))
}

#' @rdname wasm_module
#' @export
wasm_validate <- function(x) {
  call <- sys.call()
  nw_check(.Call(nw_module_load, module_bytes(x, call)), call)
  invisible(TRUE)
}

module_bytes <- function(x, call) {
  if (is.raw(x)) {
    bytes <- x
  } else if (is.character(x) && length(x) == 1 && !is.na(x)) {
    if (!file.exists(x) || dir.exists(x)) {
      nanowasm_abort(
        "nanowasm_argument_error",
        paste0("Can't find the file `", x, "`."),
        call = call
      )
    }
    size <- file.size(x)
    check_module_size(size, call)
    bytes <- readBin(x, "raw", n = size)
  } else {
    nanowasm_abort(
      "nanowasm_argument_error",
      "`x` must be a raw vector or the path to a .wasm file.",
      call = call
    )
  }
  check_module_size(length(bytes), call)
  bytes
}

check_module_size <- function(size, call) {
  max_size <- getOption("nanowasm.max_module_size", 64 * 2^20)
  if (size > max_size) {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0(
        "The module is ", format(size, big.mark = ","), " bytes, more than ",
        "the limit of ", format(max_size, big.mark = ","), " bytes set by ",
        "`options(nanowasm.max_module_size)`."
      ),
      call = call
    )
  }
}

new_module <- function(ptr, size) {
  ex <- .Call(nw_module_exports, ptr)
  im <- .Call(nw_module_imports, ptr)
  # toywasm keeps exports sorted by length, then bytes, for its lookups;
  # show them alphabetically instead. Imports stay in module order.
  ex <- lapply(ex, `[`, order(ex[[1]], method = "radix"))
  structure(
    list(
      ptr = ptr,
      size = size,
      exports = data.frame(
        name = ex[[1]], kind = ex[[2]], type = ex[[3]],
        stringsAsFactors = FALSE
      ),
      imports = data.frame(
        module = im[[1]], name = im[[2]], kind = im[[3]], type = im[[4]],
        stringsAsFactors = FALSE
      )
    ),
    class = "nanowasm_module"
  )
}

#' List a module's exports and imports
#'
#' @param x A `nanowasm_module` from [wasm_module()], or a
#'   `nanowasm_instance` from [wasm_instantiate()].
#' @return A data frame with one row per export (sorted by name) or import
#'   (in module order), and columns
#'   `name`, `kind` (`"function"`, `"memory"`, `"table"` or `"global"`) and
#'   `type`. Imports also have a `module` column. Function types are written
#'   `"(i32, i32) -> i32"`; memories and tables show their limits in pages or
#'   elements (`"min 1 max 2"`); globals show their value type, prefixed with
#'   `"mut"` if mutable.
#' @export
#' @examples
#' mod <- wasm_module(system.file("extdata", "add.wasm", package = "nanowasm"))
#' wasm_exports(mod)
#' wasm_imports(mod)
wasm_exports <- function(x) {
  as_module(x, sys.call())$exports
}

#' @rdname wasm_exports
#' @export
wasm_imports <- function(x) {
  as_module(x, sys.call())$imports
}

as_module <- function(x, call) {
  if (inherits(x, "nanowasm_instance")) {
    x <- .subset2(x, "module")
  }
  if (!inherits(x, "nanowasm_module")) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "`x` must be a nanowasm module or instance.",
      call = call
    )
  }
  x
}

#' @export
format.nanowasm_module <- function(x, ...) {
  c(
    paste0("<nanowasm_module> ", format(x$size, big.mark = ","), " bytes"),
    format_externs("exports", x$exports),
    format_externs("imports", x$imports)
  )
}

format_externs <- function(label, df) {
  if (nrow(df) == 0) {
    return(paste0(label, ": none"))
  }
  name <- if (is.null(df$module)) df$name else paste0(df$module, ".", df$name)
  c(
    paste0(label, ":"),
    paste0(
      "  ", formatC(name, width = -max(nchar(name))),
      "  ", formatC(df$kind, width = -8),
      "  ", df$type
    )
  )
}

#' @export
print.nanowasm_module <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}
