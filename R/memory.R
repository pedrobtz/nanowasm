#' Access an instance's linear memory
#'
#' `wasm_memory()` returns a handle to one of an instance's exported
#' memories. `wasm_read()` and `wasm_write()` copy vectors out of and into it,
#' and `wasm_read_string()` and `wasm_write_string()` do the same for UTF-8
#' strings. `wasm_memory_size()` and `wasm_memory_grow()` query and change
#' its size.
#'
#' Offsets are 0-based byte addresses, the same numbers a WebAssembly
#' function receives as pointers, not 1-based R indices. Every access is
#' checked against the memory's current size; one that falls outside signals
#' a `nanowasm_out_of_bounds` error and changes nothing.
#'
#' `type` gives the element type, stored little-endian as WebAssembly
#' requires:
#'
#' | `type`                        | R vector | Notes |
#' |-------------------------------|----------|-------|
#' | `"raw"`                       | raw      | |
#' | `"i8"`, `"u8"`, `"i16"`, `"u16"`, `"i32"` | integer | |
#' | `"u32"`                       | double   | |
#' | `"i64"`, `"u64"`              | double   | Values beyond \eqn{2^{53}} signal a `nanowasm_precision_error`. |
#' | `"f32"`, `"f64"`              | double   | `f32` values are rounded to single precision. |
#'
#' Writes check every element before changing any memory: integer types
#' reject `NA`, fractions and values outside the type's range.
#'
#' WebAssembly has no standard allocator. To pass data to a function, use
#' the module's own allocation export (often named `malloc` or `alloc`) to
#' get an offset, then write there.
#'
#' @param instance A `nanowasm_instance`.
#' @param name The export name of the memory. The default, `NULL`, picks the
#'   instance's only exported memory.
#' @param memory A `nanowasm_memory` from `wasm_memory()`.
#' @param offset Byte offset (0-based).
#' @param n Number of elements to read. For `wasm_read_string()`, the number
#'   of bytes, or `NULL` to read up to the first NUL byte.
#' @param type Element type; see Details.
#' @param x For `wasm_write()`, the vector to write. For
#'   `wasm_write_string()`, a single string.
#' @param nul Whether to write a terminating NUL byte after the string.
#' @param unit Report the size in `"bytes"` or in `"pages"` (64 KiB each).
#' @param pages Number of pages to add.
#' @return `wasm_memory()` returns a `nanowasm_memory`. `wasm_read()` returns
#'   a vector of length `n` and `wasm_read_string()` a string.
#'   `wasm_write()` and `wasm_write_string()` invisibly return the offset just
#'   past the bytes written. `wasm_memory_size()` returns a number, and
#'   `wasm_memory_grow()` the previous size in pages.
#' @export
#' @examples
#' mod <- wasm_module(system.file("extdata", "sum.wasm", package = "nanowasm"))
#' inst <- wasm_instantiate(mod)
#' mem <- wasm_memory(inst)
#' mem
#'
#' # Ask the module for room for 5 doubles, fill it, and sum it.
#' x <- c(1.5, 2.5, 3, 4, 5)
#' ptr <- inst$alloc(8L * length(x))
#' wasm_write(mem, ptr, x, "f64")
#' inst$sum_f64(ptr, length(x))
#' wasm_read(mem, ptr, 5, "f64")
#'
#' next_free <- wasm_write_string(mem, 1024, "héllo")
#' wasm_read_string(mem, 1024)
#' wasm_read(mem, 1024, next_free - 1024, "u8")
wasm_memory <- function(instance, name = NULL) {
  call <- sys.call()
  check_instance(instance, call)
  exports <- wasm_exports(instance)
  memories <- exports$name[exports$kind == "memory"]
  if (is.null(name)) {
    if (length(memories) != 1) {
      nanowasm_abort(
        "nanowasm_argument_error",
        if (length(memories) == 0) {
          "The instance exports no memory."
        } else {
          paste0(
            "The instance exports ", length(memories), " memories (",
            paste0("`", memories, "`", collapse = ", "), "); choose one with `name`."
          )
        },
        call = call
      )
    }
    name <- memories
  }
  check_string(name, "name", call)
  index <- nw_check(.Call(nw_memory_index, nw_ptr(instance, call), name), call)
  structure(
    list(instance = instance, name = name, index = index),
    class = "nanowasm_memory"
  )
}

memory_types <- c("raw", "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "f32", "f64")

# Arguments shared by the memory functions, checked and in C's terms.
mem_args <- function(memory, offset, call) {
  if (!inherits(memory, "nanowasm_memory")) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "`memory` must be a nanowasm memory from `wasm_memory()`.",
      call = call
    )
  }
  if (!missing(offset)) check_count(offset, "offset", call)
  list(ptr = nw_ptr(memory$instance, call), index = memory$index)
}

check_count <- function(x, arg, call) {
  if (!is.numeric(x) || length(x) != 1 || is.na(x) || x < 0 ||
    !is.finite(x) || x != floor(x)) {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0("`", arg, "` must be a single non-negative whole number."),
      call = call
    )
  }
  invisible(x)
}

check_string <- function(x, arg, call) {
  if (!is.character(x) || length(x) != 1 || is.na(x)) {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0("`", arg, "` must be a single string."),
      call = call
    )
  }
  invisible(x)
}

type_code <- function(type, call) {
  if (!is.character(type) || length(type) != 1 || !type %in% memory_types) {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0(
        "`type` must be one of ",
        paste0("\"", memory_types, "\"", collapse = ", "), "."
      ),
      call = call
    )
  }
  match(type, memory_types) - 1L
}

#' @rdname wasm_memory
#' @export
wasm_read <- function(memory, offset, n, type = "u8") {
  call <- sys.call()
  m <- mem_args(memory, offset, call)
  check_count(n, "n", call)
  nw_check(.Call(
    nw_memory_read, m$ptr, m$index, as.double(offset), as.double(n),
    type_code(type, call)
  ), call)
}

#' @rdname wasm_memory
#' @export
wasm_write <- function(memory, offset, x, type = "u8") {
  call <- sys.call()
  m <- mem_args(memory, offset, call)
  code <- type_code(type, call)
  invisible(nw_check(.Call(
    nw_memory_write, m$ptr, m$index, as.double(offset), x, code
  ), call))
}

#' @rdname wasm_memory
#' @export
wasm_read_string <- function(memory, offset, n = NULL) {
  call <- sys.call()
  m <- mem_args(memory, offset, call)
  if (is.null(n)) {
    n <- nw_check(.Call(nw_memory_strlen, m$ptr, m$index, as.double(offset)), call)
  } else {
    check_count(n, "n", call)
  }
  bytes <- nw_check(.Call(
    nw_memory_read, m$ptr, m$index, as.double(offset), as.double(n),
    type_code("raw", call)
  ), call)
  if (any(bytes == 0)) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "The string contains a NUL byte; read it as raw bytes instead.",
      call = call
    )
  }
  s <- rawToChar(bytes)
  Encoding(s) <- "UTF-8"
  if (!validUTF8(s)) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "The bytes are not valid UTF-8; read them as raw bytes instead.",
      call = call
    )
  }
  s
}

#' @rdname wasm_memory
#' @export
wasm_write_string <- function(memory, offset, x, nul = TRUE) {
  call <- sys.call()
  m <- mem_args(memory, offset, call)
  check_string(x, "x", call)
  bytes <- charToRaw(enc2utf8(x))
  if (isTRUE(nul)) bytes <- c(bytes, as.raw(0))
  invisible(nw_check(.Call(
    nw_memory_write, m$ptr, m$index, as.double(offset), bytes,
    type_code("raw", call)
  ), call))
}

#' @rdname wasm_memory
#' @export
wasm_memory_size <- function(memory, unit = c("bytes", "pages")) {
  call <- sys.call()
  unit <- match.arg(unit)
  m <- mem_args(memory, call = call)
  size <- .Call(nw_memory_size, m$ptr, m$index)
  if (unit == "bytes") size[[1]] else size[[2]]
}

#' @rdname wasm_memory
#' @export
wasm_memory_grow <- function(memory, pages) {
  call <- sys.call()
  m <- mem_args(memory, call = call)
  check_count(pages, "pages", call)
  nw_check(.Call(nw_memory_grow, m$ptr, m$index, as.double(pages)), call)
}

#' @export
format.nanowasm_memory <- function(x, ...) {
  if (!.Call(nw_ptr_is_live, .subset2(x$instance, "ptr"))) {
    return("<nanowasm_memory> (invalid)")
  }
  size <- wasm_memory_size(x, "pages")
  paste0(
    "<nanowasm_memory> `", x$name, "`: ", format(size, big.mark = ","),
    " page", if (size != 1) "s", " (", format_bytes(size * 65536), ")"
  )
}

#' @export
print.nanowasm_memory <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}
