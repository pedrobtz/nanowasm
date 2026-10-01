#' Run WASI programs
#'
#' WASI (the WebAssembly System Interface, "preview 1") is how WebAssembly
#' programs compiled from C, C++, Rust and other languages reach the outside
#' world: command-line arguments, environment variables, standard input and
#' output, clocks, random numbers and files. `wasm_wasi()` describes what a
#' program may see; `wasm_instantiate(wasi = )` provides it to an instance;
#' `wasm_wasi_start()` runs the program; and `wasm_run()` does all three in one
#' call.
#'
#' nanowasm implements WASI itself, in R, rather than giving the program the
#' operating system's:
#'
#' * Arguments and environment variables are only those you pass.
#' * Standard output and error go to the R console (or are captured or
#'   discarded); standard input comes from `stdin`, or is empty.
#' * Files are reachable only inside the directories in `dirs`, read-only
#'   unless `writable = TRUE`. Paths can't leave a granted directory, whether
#'   through `..`, absolute paths or symbolic links. Hard and symbolic links
#'   can't be created.
#' * Clocks are R's, and random numbers come from R's random number generator,
#'   so [set.seed()] makes a program's randomness reproducible.
#' * Sockets and signals are not available.
#'
#' Functions a program calls that nanowasm doesn't provide return WASI's
#' `ENOSYS` or `ENOTSUP` error code, as a host without them would.
#'
#' A WASI environment holds the program's open files and its output, so it
#' belongs to one instance; create a new one for each instance.
#'
#' @param args Command-line arguments, after the program name.
#' @param env Environment variables, as a named character vector.
#' @param stdin Standard input: `NULL` for none, a character vector (written
#'   as lines) or a raw vector.
#' @param stdout,stderr Where the program's output goes: `"console"` (the R
#'   console, as it is written), `"capture"` (kept for [wasm_wasi_output()]),
#'   or `"discard"`.
#' @param dirs Directories the program may use, as a character vector of host
#'   paths named by the path the program sees them at (`c("/data" = "~/x")`).
#'   A single unnamed directory is seen as the program's current directory, so
#'   relative paths resolve inside it.
#' @param writable Whether the program may create, change and delete files in
#'   `dirs`.
#' @param program The program name the module sees as its first argument.
#' @return `wasm_wasi()` returns a `nanowasm_wasi` object.
#' @seealso [wasm_run()] to run a WASI program in one call.
#' @export
#' @examples
#' hello <- system.file("extdata", "hello-wasi.wasm", package = "nanowasm")
#'
#' wasi <- wasm_wasi(args = c("from", "R"), env = c(GREETING = "Hello"))
#' inst <- wasm_instantiate(wasm_module(hello), wasi = wasi)
#' wasm_wasi_start(inst)
#'
#' # Capture the output instead.
#' wasi <- wasm_wasi(args = "quietly", stdout = "capture")
#' inst <- wasm_instantiate(wasm_module(hello), wasi = wasi)
#' wasm_wasi_start(inst)
#' wasm_wasi_output(wasi)
wasm_wasi <- function(args = character(), env = character(), stdin = NULL,
                      stdout = c("console", "capture", "discard"),
                      stderr = c("console", "capture", "discard"),
                      dirs = character(), writable = FALSE,
                      program = "main") {
  call <- sys.call()
  check_character(args, "args", call)
  check_character(env, "env", call)
  if (length(env) > 0 && (is.null(names(env)) || any(!nzchar(names(env))))) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "`env` must be a named character vector, such as `c(HOME = \"/\")`.",
      call = call
    )
  }
  check_string(program, "program", call)
  if (!is.logical(writable) || length(writable) != 1 || is.na(writable)) {
    nanowasm_abort("nanowasm_argument_error", "`writable` must be `TRUE` or `FALSE`.", call = call)
  }
  stdout <- match.arg(stdout)
  stderr <- match.arg(stderr)

  st <- new.env(parent = emptyenv())
  st$argv <- enc2utf8(c(program, args))
  st$environ <- if (length(env)) enc2utf8(paste0(names(env), "=", unname(env))) else character()
  st$stdin <- stdin_bytes(stdin, call)
  st$stdin_pos <- 0
  st$mode <- c(`1` = stdout, `2` = stderr)
  st$captured <- list(`1` = raw(), `2` = raw())
  st$pending <- list(`1` = raw(), `2` = raw())
  st$writable <- writable
  st$fds <- list(
    `0` = list(kind = "stdin"),
    `1` = list(kind = "stdout"),
    `2` = list(kind = "stderr")
  )
  st$exit_status <- NULL
  st$bound <- FALSE
  st$mem <- NULL
  st$clock0 <- proc.time()[["elapsed"]]

  preopens <- preopen_dirs(dirs, call)
  for (i in seq_along(preopens$host)) {
    st$fds[[as.character(2L + i)]] <- list(
      kind = "dir", root = preopens$host[[i]], rel = character(),
      preopen = preopens$guest[[i]]
    )
  }
  structure(list(state = st), class = "nanowasm_wasi")
}

check_character <- function(x, arg, call) {
  if (!is.character(x) || anyNA(x)) {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0("`", arg, "` must be a character vector without missing values."),
      call = call
    )
  }
}

stdin_bytes <- function(stdin, call) {
  if (is.null(stdin)) {
    raw()
  } else if (is.raw(stdin)) {
    stdin
  } else if (is.character(stdin) && !anyNA(stdin)) {
    charToRaw(enc2utf8(paste0(stdin, "\n", collapse = "")))
  } else {
    nanowasm_abort(
      "nanowasm_argument_error",
      "`stdin` must be `NULL`, a character vector or a raw vector.",
      call = call
    )
  }
}

preopen_dirs <- function(dirs, call) {
  check_character(dirs, "dirs", call)
  if (length(dirs) == 0) {
    return(list(host = character(), guest = character()))
  }
  guest <- names(dirs)
  if (is.null(guest)) {
    if (length(dirs) > 1) {
      nanowasm_abort(
        "nanowasm_argument_error",
        "`dirs` must be named when it has more than one directory, such as `c(\"/in\" = \"data\", \"/out\" = \"results\")`.",
        call = call
      )
    }
    guest <- "."
  }
  if (any(!nzchar(guest)) || anyDuplicated(guest)) {
    nanowasm_abort("nanowasm_argument_error", "The names of `dirs` must be unique and non-empty.", call = call)
  }
  missing <- !dir.exists(dirs)
  if (any(missing)) {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0("Can't find the director", if (sum(missing) > 1) "ies " else "y ",
             paste0("`", dirs[missing], "`", collapse = ", "), "."),
      call = call
    )
  }
  list(host = normalizePath(unname(dirs), winslash = "/"), guest = guest)
}

#' @rdname wasm_wasi
#' @param instance An instance created with `wasm_instantiate(wasi = )`.
#' @return `wasm_wasi_start()` runs the program's `_start` function and
#'   returns its exit status: 0 when `_start` returns, or the status it passed
#'   to `exit()`. It returns invisibly when the status is 0.
#' @export
wasm_wasi_start <- function(instance) {
  call <- sys.call()
  check_instance(instance, call)
  wasi <- .subset2(instance, "wasi")
  if (is.null(wasi)) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "The instance has no WASI environment; create it with `wasm_instantiate(wasi = wasm_wasi())`.",
      call = call
    )
  }
  exports <- wasm_exports(instance)
  if (!"_start" %in% exports$name[exports$kind == "function"]) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "The module is not a WASI command: it doesn't export `_start`.",
      call = call
    )
  }
  st <- wasi$state
  status <- tryCatch(
    {
      nw_call_impl(instance, "_start", list(), call)
      0L
    },
    nanowasm_host_error = function(e) {
      if (inherits(e$parent, "nanowasm_wasi_exit")) e$parent$status else stop(e)
    },
    finally = wasi_flush(st)
  )
  st$exit_status <- status
  if (status == 0L) invisible(status) else status
}

#' @rdname wasm_wasi
#' @param wasi A `nanowasm_wasi` object.
#' @param stream Which captured stream to return.
#' @return `wasm_wasi_output()` returns what the program has written to a
#'   captured stream so far, as a string.
#' @export
wasm_wasi_output <- function(wasi, stream = c("stdout", "stderr")) {
  call <- sys.call()
  if (!inherits(wasi, "nanowasm_wasi")) {
    nanowasm_abort("nanowasm_argument_error", "`wasi` must be created by `wasm_wasi()`.", call = call)
  }
  stream <- match.arg(stream)
  fd <- if (stream == "stdout") "1" else "2"
  if (wasi$state$mode[[fd]] != "capture") {
    nanowasm_abort(
      "nanowasm_argument_error",
      paste0("`", stream, "` is not captured; use `wasm_wasi(", stream, " = \"capture\")`."),
      call = call
    )
  }
  bytes_to_text(wasi$state$captured[[fd]])
}

#' Run a WASI program
#'
#' `wasm_run()` runs a WASI command module (one that exports `_start`, as
#' programs built with wasi-sdk or Rust's `wasm32-wasip1` target do) from
#' start to finish, and returns its exit status and captured output. It is
#' `wasm_wasi()`, `wasm_instantiate()` and `wasm_wasi_start()` in one call;
#' see [wasm_wasi()] for what the program can and can't reach.
#'
#' @param module A `nanowasm_module`, or anything [wasm_module()] accepts.
#' @inheritParams wasm_wasi
#' @param stdout,stderr Where the program's output goes: `"capture"` (the
#'   default; returned in the result), `"console"` or `"discard"`.
#' @param imports Other imports the module needs, as for [wasm_instantiate()].
#' @param limits Resource limits from [wasm_limits()].
#' @return A `nanowasm_run` object: a list with the exit `status` and, for
#'   captured streams, the `stdout` and `stderr` text.
#' @export
#' @examples
#' hello <- system.file("extdata", "hello-wasi.wasm", package = "nanowasm")
#' res <- wasm_run(hello, args = c("from", "R"), env = c(GREETING = "Hi"))
#' res
#' res$stdout
#'
#' # The program can only see the directories you grant.
#' dir <- tempfile()
#' dir.create(dir)
#' writeLines(c("a,b", "1,2"), file.path(dir, "data.csv"))
#' cat_wasm <- system.file("extdata", "cat-wasi.wasm", package = "nanowasm")
#' wasm_run(cat_wasm, args = "data.csv", dirs = dir)$stdout
#' wasm_run(cat_wasm, args = "../secret.txt", dirs = dir)
wasm_run <- function(module, args = character(), env = character(), stdin = NULL,
                     dirs = character(), writable = FALSE,
                     stdout = c("capture", "console", "discard"),
                     stderr = c("capture", "console", "discard"),
                     imports = list(), limits = NULL, program = "main") {
  if (!inherits(module, "nanowasm_module")) module <- wasm_module(module)
  wasi <- wasm_wasi(
    args = args, env = env, stdin = stdin,
    stdout = match.arg(stdout), stderr = match.arg(stderr),
    dirs = dirs, writable = writable, program = program
  )
  inst <- wasm_instantiate(module, imports = imports, limits = limits, wasi = wasi)
  status <- wasm_wasi_start(inst)
  st <- wasi$state
  structure(
    list(
      status = status,
      stdout = if (st$mode[["1"]] == "capture") bytes_to_text(st$captured[["1"]]),
      stderr = if (st$mode[["2"]] == "capture") bytes_to_text(st$captured[["2"]])
    ),
    class = "nanowasm_run"
  )
}

#' @export
format.nanowasm_wasi <- function(x, ...) {
  st <- x$state
  pre <- Filter(function(f) !is.null(f$preopen), st$fds)
  c(
    "<nanowasm_wasi>",
    paste0("  args:   ", paste(encodeString(st$argv, quote = "\""), collapse = " ")),
    paste0("  env:    ", if (length(st$environ)) paste(st$environ, collapse = " ") else "(none)"),
    paste0("  stdin:  ", length(st$stdin), " bytes"),
    paste0("  stdout: ", st$mode[["1"]], ", stderr: ", st$mode[["2"]]),
    paste0("  dirs:   ", if (length(pre)) {
      paste0(vapply(pre, function(f) paste0(f$preopen, " -> ", f$root), ""), collapse = ", ")
    } else "(none)", if (length(pre)) paste0(" (", if (st$writable) "writable" else "read-only", ")")),
    if (!is.null(st$exit_status)) paste0("  exited with status ", st$exit_status)
  )
}

#' @export
print.nanowasm_wasi <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}

#' @export
print.nanowasm_run <- function(x, ...) {
  cat("<nanowasm_run> exit status ", x$status, "\n", sep = "")
  for (s in c("stdout", "stderr")) {
    if (!is.null(x[[s]]) && nzchar(x[[s]])) {
      cat("-- ", s, " --\n", x[[s]], if (!endsWith(x[[s]], "\n")) "\n", sep = "")
    }
  }
  invisible(x)
}

# The wasi_snapshot_preview1 imports for a WASI environment, ready to merge
# into wasm_instantiate()'s imports. Binds the environment to one instance.
wasi_imports <- function(wasi, call) {
  if (!inherits(wasi, "nanowasm_wasi")) {
    nanowasm_abort("nanowasm_argument_error", "`wasi` must be created by `wasm_wasi()`.", call = call)
  }
  st <- wasi$state
  if (st$bound) {
    nanowasm_abort(
      "nanowasm_argument_error",
      "This WASI environment already belongs to another instance; create a new one with `wasm_wasi()`.",
      call = call
    )
  }
  st$bound <- TRUE
  list(wasi_snapshot_preview1 = wasi_functions(st))
}

# --------------------------------------------------------------- constants

wasi_errno <- c(
  SUCCESS = 0L, ACCES = 2L, BADF = 8L, EXIST = 20L, FAULT = 21L, INVAL = 28L,
  IO = 29L, ISDIR = 31L, NOENT = 44L, NOSYS = 52L, NOTDIR = 54L,
  NOTEMPTY = 55L, NOTSUP = 58L, SPIPE = 70L, NOTCAPABLE = 76L
)

wasi_filetype <- c(UNKNOWN = 0L, CHARACTER_DEVICE = 2L, DIRECTORY = 3L, REGULAR_FILE = 4L)

# Every right in WASI preview 1 (bits 0-29).
wasi_all_rights <- 2^30 - 1

# ------------------------------------------------------------ byte helpers

le_u32 <- function(x) {
  x <- as.numeric(x)
  writeBin(as.integer(ifelse(x >= 2^31, x - 2^32, x)), raw(), size = 4, endian = "little")
}

le_u16 <- function(x) writeBin(as.integer(x), raw(), size = 2, endian = "little")

# Values above 2^53 are rounded by the double they arrive in; that only
# affects clocks, whose low bits are noise anyway.
le_u64 <- function(x) {
  x <- as.numeric(x)
  hi <- floor(x / 2^32)
  lo <- x - hi * 2^32
  le_u32(as.vector(rbind(lo, hi)))
}

bytes_to_text <- function(bytes) {
  bytes <- bytes[bytes != as.raw(0)]
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  text
}

# ------------------------------------------------------------------- stdio

# Write program output to the console, holding back an incomplete UTF-8
# character at the end of a write until the rest arrives.
wasi_emit <- function(st, fd, bytes) {
  mode <- st$mode[[fd]]
  if (mode == "discard") return(invisible())
  if (mode == "capture") {
    st$captured[[fd]] <- c(st$captured[[fd]], bytes)
    return(invisible())
  }
  bytes <- c(st$pending[[fd]], bytes)
  keep <- utf8_complete_length(bytes)
  st$pending[[fd]] <- bytes[seq_len(length(bytes) - keep) + keep]
  if (keep > 0) {
    text <- bytes_to_text(bytes[seq_len(keep)])
    if (fd == "1") cat(text) else cat(text, file = stderr())
  }
  invisible()
}

# How many leading bytes form complete UTF-8 characters.
utf8_complete_length <- function(bytes) {
  n <- length(bytes)
  for (back in seq_len(min(3, n))) {
    b <- as.integer(bytes[[n - back + 1]])
    if (b < 0x80) return(n)
    if (b >= 0xC0) {
      need <- if (b >= 0xF0) 4 else if (b >= 0xE0) 3 else 2
      return(if (back >= need) n else n - back)
    }
  }
  n
}

wasi_flush <- function(st) {
  for (fd in c("1", "2")) {
    if (st$mode[[fd]] == "console" && length(st$pending[[fd]])) {
      text <- bytes_to_text(st$pending[[fd]])
      st$pending[[fd]] <- raw()
      if (fd == "1") cat(text) else cat(text, file = stderr())
    }
  }
  for (f in st$fds) {
    if (!is.null(f$con)) try(flush(f$con), silent = TRUE)
  }
  invisible()
}

# -------------------------------------------------------------- functions

# The 46 functions of wasi_snapshot_preview1, closing over the state `st`.
# Each returns a WASI errno. A memory access outside the module's memory
# returns EFAULT; proc_exit unwinds with a nanowasm_wasi_exit condition.
wasi_functions <- function(st) {
  mem <- function(caller) {
    if (is.null(st$mem)) st$mem <- caller$memory()
    st$mem
  }
  rd_u32 <- function(m, off, n = 1) wasm_read(m, off, n, "u32")
  wr <- function(m, off, bytes) wasm_write(m, off, bytes, "raw")
  rd_str <- function(m, ptr, len) {
    bytes <- wasm_read(m, ptr, len, "raw")
    text <- rawToChar(bytes[bytes != as.raw(0)])
    Encoding(text) <- "UTF-8"
    text
  }
  fd_get <- function(fd) st$fds[[as.character(fd)]]

  # Wrap an implementation (whose last argument is `caller`) with its WASI
  # signature. A memory access outside the module's memory is EFAULT.
  # i64 arguments beyond 2^53 (nanosecond timestamps, some rights masks)
  # arrive rounded to a double instead of failing the call.
  fn <- function(params, body, results = "i32") {
    f <- wasm_func(
      function(..., caller) {
        tryCatch(
          as.integer(body(..., caller = caller)),
          nanowasm_out_of_bounds = function(e) wasi_errno[["FAULT"]]
        )
      },
      params = params, results = results
    )
    f$lossy_i64 <- TRUE
    f
  }

  nosys <- function(params) fn(params, function(..., caller) wasi_errno[["NOSYS"]])
  notsup <- function(params) fn(params, function(..., caller) wasi_errno[["NOTSUP"]])

  # Strings laid out as an array of pointers plus NUL-terminated contents.
  string_sizes <- function(strings) {
    function(count_ptr, size_ptr, caller) {
      m <- mem(caller)
      wr(m, count_ptr, le_u32(length(strings)))
      wr(m, size_ptr, le_u32(sum(nchar(strings, type = "bytes") + 1)))
      0L
    }
  }
  string_get <- function(strings) {
    function(ptrs, buf, caller) {
      m <- mem(caller)
      bytes <- lapply(strings, function(s) c(charToRaw(s), as.raw(0)))
      offsets <- buf + c(0, cumsum(lengths(bytes)))[seq_along(bytes)]
      if (length(strings)) {
        wr(m, ptrs, le_u32(offsets))
        wr(m, buf, unlist(bytes))
      }
      0L
    }
  }

  # iovec arrays: (buf, len) pairs.
  iovs_read <- function(m, iovs, n) {
    if (n == 0) return(matrix(numeric(), ncol = 2))
    matrix(rd_u32(m, iovs, 2 * n), ncol = 2, byrow = TRUE)
  }
  gather <- function(m, iov) {
    unlist(lapply(seq_len(nrow(iov)), function(i) wasm_read(m, iov[i, 1], iov[i, 2], "raw")))
  }
  scatter <- function(m, iov, bytes) {
    pos <- 0
    for (i in seq_len(nrow(iov))) {
      take <- min(iov[i, 2], length(bytes) - pos)
      if (take <= 0) break
      wr(m, iov[i, 1], bytes[pos + seq_len(take)])
      pos <- pos + take
    }
    pos
  }

  # Bytes from a source, at a position, without moving it.
  read_from <- function(f, fd, n, at = NULL) {
    if (f$kind == "stdin") {
      start <- st$stdin_pos
      take <- max(0, min(n, length(st$stdin) - start))
      st$stdin_pos <- start + take
      return(st$stdin[start + seq_len(take)])
    }
    pos <- if (is.null(at)) f$pos else at
    seek(f$con, pos, origin = "start", rw = "read")
    bytes <- readBin(f$con, "raw", n)
    if (is.null(at)) {
      f$pos <- pos + length(bytes)
      st$fds[[as.character(fd)]] <- f
    }
    bytes
  }
  write_to <- function(f, fd, bytes, at = NULL) {
    if (f$kind %in% c("stdout", "stderr")) {
      wasi_emit(st, as.character(if (f$kind == "stdout") 1 else 2), bytes)
      return(length(bytes))
    }
    pos <- if (!is.null(at)) at else if (isTRUE(f$append)) file_size(f) else f$pos
    seek(f$con, pos, origin = "start", rw = "write")
    writeBin(bytes, f$con)
    flush(f$con)
    if (is.null(at)) {
      f$pos <- pos + length(bytes)
      st$fds[[as.character(fd)]] <- f
    }
    length(bytes)
  }
  file_size <- function(f) {
    size <- file.size(f$host)
    if (is.na(size)) 0 else size
  }

  # Resolve a path relative to a directory fd, staying inside its root.
  # Returns list(host, rel, root) or an errno.
  resolve <- function(dirfd, m, ptr, len) {
    d <- fd_get(dirfd)
    if (is.null(d)) return(wasi_errno[["BADF"]])
    if (d$kind != "dir") return(wasi_errno[["NOTDIR"]])
    path <- rd_str(m, ptr, len)
    if (startsWith(path, "/") || grepl("^[A-Za-z]:", path) || grepl("\\\\", path)) {
      return(wasi_errno[["NOTCAPABLE"]])
    }
    rel <- d$rel
    for (part in strsplit(path, "/", fixed = TRUE)[[1]]) {
      if (part %in% c("", ".")) next
      if (part == "..") {
        if (!length(rel)) return(wasi_errno[["NOTCAPABLE"]])
        rel <- rel[-length(rel)]
      } else {
        rel <- c(rel, part)
      }
    }
    host <- if (length(rel)) do.call(file.path, as.list(c(d$root, rel))) else d$root
    # A symbolic link must not lead outside the root either.
    probe <- host
    while (!file.exists(probe) && probe != d$root) probe <- dirname(probe)
    real <- normalizePath(probe, winslash = "/", mustWork = FALSE)
    root <- d$root
    if (real != root && !startsWith(real, paste0(sub("/$", "", root), "/"))) {
      return(wasi_errno[["NOTCAPABLE"]])
    }
    list(host = host, rel = rel, root = root)
  }
  denied <- function() if (!st$writable) wasi_errno[["NOTCAPABLE"]]

  filetype_of <- function(f) {
    switch(f$kind,
      stdin = , stdout = , stderr = wasi_filetype[["CHARACTER_DEVICE"]],
      dir = wasi_filetype[["DIRECTORY"]],
      file = wasi_filetype[["REGULAR_FILE"]]
    )
  }
  filestat_bytes <- function(host, filetype = NULL) {
    info <- file.info(host, extra_cols = FALSE)
    if (is.null(filetype)) {
      filetype <- if (isTRUE(info$isdir)) wasi_filetype[["DIRECTORY"]] else wasi_filetype[["REGULAR_FILE"]]
    }
    ns <- function(t) if (is.na(t)) 0 else max(0, round(as.numeric(t) * 1e9))
    c(
      le_u64(0), le_u64(0),
      as.raw(filetype), raw(7),
      le_u64(1),
      le_u64(if (is.na(info$size)) 0 else info$size),
      le_u64(ns(info$atime)), le_u64(ns(info$mtime)), le_u64(ns(info$ctime))
    )
  }
  new_fd <- function(entry) {
    used <- as.integer(names(st$fds))
    fd <- min(setdiff(seq_len(max(used) + 1L), used))
    st$fds[[as.character(fd)]] <- entry
    fd
  }
  close_fd <- function(fd) {
    f <- fd_get(fd)
    if (!is.null(f$con)) try(close(f$con), silent = TRUE)
    st$fds[[as.character(fd)]] <- NULL
  }

  list(
    args_get = fn(c("i32", "i32"), string_get(st$argv)),
    args_sizes_get = fn(c("i32", "i32"), string_sizes(st$argv)),
    environ_get = fn(c("i32", "i32"), string_get(st$environ)),
    environ_sizes_get = fn(c("i32", "i32"), string_sizes(st$environ)),

    clock_res_get = fn(c("i32", "i32"), function(id, ptr, caller) {
      if (!id %in% 0:3) return(wasi_errno[["INVAL"]])
      wr(mem(caller), ptr, le_u64(1000))
      0L
    }),
    clock_time_get = fn(c("i32", "i64", "i32"), function(id, precision, ptr, caller) {
      t <- switch(as.character(id),
        "0" = as.numeric(Sys.time()),
        "1" = proc.time()[["elapsed"]] - st$clock0,
        "2" = , "3" = sum(proc.time()[c("user.self", "sys.self")]),
        NULL
      )
      if (is.null(t)) return(wasi_errno[["INVAL"]])
      wr(mem(caller), ptr, le_u64(round(t * 1e9)))
      0L
    }),

    fd_advise = fn(c("i32", "i64", "i64", "i32"), function(fd, offset, len, advice, caller) {
      if (is.null(fd_get(fd))) wasi_errno[["BADF"]] else 0L
    }),
    fd_allocate = notsup(c("i32", "i64", "i64")),
    fd_close = fn("i32", function(fd, caller) {
      if (is.null(fd_get(fd))) return(wasi_errno[["BADF"]])
      close_fd(fd)
      0L
    }),
    fd_datasync = fn("i32", function(fd, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (!is.null(f$con)) flush(f$con)
      0L
    }),
    fd_fdstat_get = fn(c("i32", "i32"), function(fd, ptr, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      flags <- if (isTRUE(f$append)) 1L else 0L
      wr(mem(caller), ptr, c(
        as.raw(filetype_of(f)), raw(1), le_u16(flags), raw(4),
        le_u64(wasi_all_rights), le_u64(wasi_all_rights)
      ))
      0L
    }),
    fd_fdstat_set_flags = fn(c("i32", "i32"), function(fd, flags, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (f$kind == "file") {
        f$append <- bitwAnd(flags, 1L) != 0
        st$fds[[as.character(fd)]] <- f
      }
      0L
    }),
    fd_fdstat_set_rights = fn(c("i32", "i64", "i64"), function(fd, base, inheriting, caller) {
      if (is.null(fd_get(fd))) wasi_errno[["BADF"]] else 0L
    }),
    fd_filestat_get = fn(c("i32", "i32"), function(fd, ptr, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      bytes <- if (f$kind %in% c("dir", "file")) {
        filestat_bytes(if (f$kind == "dir") do.call(file.path, as.list(c(f$root, f$rel))) else f$host)
      } else {
        c(raw(16), as.raw(wasi_filetype[["CHARACTER_DEVICE"]]), raw(47))
      }
      wr(mem(caller), ptr, bytes)
      0L
    }),
    fd_filestat_set_size = fn(c("i32", "i64"), function(fd, size, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (f$kind != "file") return(wasi_errno[["INVAL"]])
      if (!isTRUE(f$writable)) return(wasi_errno[["NOTCAPABLE"]])
      current <- file_size(f)
      if (size < current) {
        seek(f$con, size, origin = "start", rw = "write")
        truncate(f$con)
      } else if (size > current) {
        seek(f$con, current, origin = "start", rw = "write")
        writeBin(raw(size - current), f$con)
      }
      flush(f$con)
      0L
    }),
    fd_filestat_set_times = fn(c("i32", "i64", "i64", "i32"), function(fd, atim, mtim, flags, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (f$kind != "file") return(0L)
      if (!isTRUE(f$writable)) return(wasi_errno[["NOTCAPABLE"]])
      set_mtime(f$host, mtim, flags)
    }),
    fd_pread = fn(c("i32", "i32", "i32", "i64", "i32"), function(fd, iovs, n, offset, nread, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (f$kind != "file") return(if (f$kind == "dir") wasi_errno[["ISDIR"]] else wasi_errno[["SPIPE"]])
      m <- mem(caller)
      iov <- iovs_read(m, iovs, n)
      bytes <- read_from(f, fd, sum(iov[, 2]), at = offset)
      wr(m, nread, le_u32(scatter(m, iov, bytes)))
      0L
    }),
    fd_prestat_get = fn(c("i32", "i32"), function(fd, ptr, caller) {
      f <- fd_get(fd)
      if (is.null(f) || is.null(f$preopen)) return(wasi_errno[["BADF"]])
      wr(mem(caller), ptr, c(raw(4), le_u32(nchar(f$preopen, type = "bytes"))))
      0L
    }),
    fd_prestat_dir_name = fn(c("i32", "i32", "i32"), function(fd, ptr, len, caller) {
      f <- fd_get(fd)
      if (is.null(f) || is.null(f$preopen)) return(wasi_errno[["BADF"]])
      name <- charToRaw(enc2utf8(f$preopen))
      if (len < length(name)) return(wasi_errno[["INVAL"]])
      wr(mem(caller), ptr, name)
      0L
    }),
    fd_pwrite = fn(c("i32", "i32", "i32", "i64", "i32"), function(fd, iovs, n, offset, nwritten, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (f$kind != "file") return(if (f$kind == "dir") wasi_errno[["ISDIR"]] else wasi_errno[["SPIPE"]])
      if (!isTRUE(f$writable)) return(wasi_errno[["NOTCAPABLE"]])
      m <- mem(caller)
      written <- write_to(f, fd, gather(m, iovs_read(m, iovs, n)), at = offset)
      wr(m, nwritten, le_u32(written))
      0L
    }),
    fd_read = fn(c("i32", "i32", "i32", "i32"), function(fd, iovs, n, nread, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (f$kind == "dir") return(wasi_errno[["ISDIR"]])
      if (f$kind %in% c("stdout", "stderr")) return(wasi_errno[["BADF"]])
      m <- mem(caller)
      iov <- iovs_read(m, iovs, n)
      bytes <- read_from(f, fd, sum(iov[, 2]))
      wr(m, nread, le_u32(scatter(m, iov, bytes)))
      0L
    }),
    fd_readdir = fn(c("i32", "i32", "i32", "i64", "i32"), function(fd, buf, len, cookie, used, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (f$kind != "dir") return(wasi_errno[["NOTDIR"]])
      host <- do.call(file.path, as.list(c(f$root, f$rel)))
      names <- c(".", "..", sort(list.files(host, all.files = TRUE, no.. = TRUE)))
      isdir <- c(TRUE, TRUE, dir.exists(file.path(host, names[-(1:2)])))
      entries <- seq_along(names)[seq_along(names) > cookie]
      bytes <- unlist(lapply(entries, function(i) {
        name <- charToRaw(enc2utf8(names[[i]]))
        c(
          le_u64(i), le_u64(0), le_u32(length(name)),
          as.raw(if (isdir[[i]]) wasi_filetype[["DIRECTORY"]] else wasi_filetype[["REGULAR_FILE"]]),
          raw(3), name
        )
      }))
      bytes <- bytes[seq_len(min(length(bytes), len))]
      m <- mem(caller)
      if (length(bytes)) wr(m, buf, bytes)
      wr(m, used, le_u32(length(bytes)))
      0L
    }),
    fd_renumber = fn(c("i32", "i32"), function(from, to, caller) {
      f <- fd_get(from)
      if (is.null(f) || is.null(fd_get(to))) return(wasi_errno[["BADF"]])
      if (from != to) {
        close_fd(to)
        st$fds[[as.character(to)]] <- f
        st$fds[[as.character(from)]] <- NULL
      }
      0L
    }),
    fd_seek = fn(c("i32", "i64", "i32", "i32"), function(fd, offset, whence, newoffset, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (f$kind != "file") return(if (f$kind == "dir") wasi_errno[["BADF"]] else wasi_errno[["SPIPE"]])
      base <- switch(as.character(whence), "0" = 0, "1" = f$pos, "2" = file_size(f), NULL)
      if (is.null(base) || base + offset < 0) return(wasi_errno[["INVAL"]])
      f$pos <- base + offset
      st$fds[[as.character(fd)]] <- f
      wr(mem(caller), newoffset, le_u64(f$pos))
      0L
    }),
    fd_sync = fn("i32", function(fd, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (!is.null(f$con)) flush(f$con)
      0L
    }),
    fd_tell = fn(c("i32", "i32"), function(fd, ptr, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (f$kind != "file") return(wasi_errno[["SPIPE"]])
      wr(mem(caller), ptr, le_u64(f$pos))
      0L
    }),
    fd_write = fn(c("i32", "i32", "i32", "i32"), function(fd, iovs, n, nwritten, caller) {
      f <- fd_get(fd)
      if (is.null(f)) return(wasi_errno[["BADF"]])
      if (f$kind == "dir") return(wasi_errno[["ISDIR"]])
      if (f$kind == "stdin") return(wasi_errno[["BADF"]])
      if (f$kind == "file" && !isTRUE(f$writable)) return(wasi_errno[["NOTCAPABLE"]])
      m <- mem(caller)
      written <- write_to(f, fd, gather(m, iovs_read(m, iovs, n)))
      wr(m, nwritten, le_u32(written))
      0L
    }),

    path_create_directory = fn(c("i32", "i32", "i32"), function(fd, ptr, len, caller) {
      if (!is.null(denied())) return(denied())
      p <- resolve(fd, mem(caller), ptr, len)
      if (!is.list(p)) return(p)
      if (file.exists(p$host)) return(wasi_errno[["EXIST"]])
      if (!dir.create(p$host, showWarnings = FALSE)) return(wasi_errno[["NOENT"]])
      0L
    }),
    path_filestat_get = fn(c("i32", "i32", "i32", "i32", "i32"), function(fd, flags, ptr, len, buf, caller) {
      m <- mem(caller)
      p <- resolve(fd, m, ptr, len)
      if (!is.list(p)) return(p)
      if (!file.exists(p$host)) return(wasi_errno[["NOENT"]])
      wr(m, buf, filestat_bytes(p$host))
      0L
    }),
    path_filestat_set_times = fn(
      c("i32", "i32", "i32", "i32", "i64", "i64", "i32"),
      function(fd, flags, ptr, len, atim, mtim, fst, caller) {
        if (!is.null(denied())) return(denied())
        p <- resolve(fd, mem(caller), ptr, len)
        if (!is.list(p)) return(p)
        if (!file.exists(p$host)) return(wasi_errno[["NOENT"]])
        set_mtime(p$host, mtim, fst)
      }
    ),
    path_link = notsup(c("i32", "i32", "i32", "i32", "i32", "i32", "i32")),
    path_open = fn(
      c("i32", "i32", "i32", "i32", "i32", "i64", "i64", "i32", "i32"),
      function(fd, dirflags, ptr, len, oflags, rights, inheriting, fdflags, out, caller) {
        m <- mem(caller)
        p <- resolve(fd, m, ptr, len)
        if (!is.list(p)) return(p)
        creat <- bitwAnd(oflags, 1L) != 0
        want_dir <- bitwAnd(oflags, 2L) != 0
        excl <- bitwAnd(oflags, 4L) != 0
        trunc <- bitwAnd(oflags, 8L) != 0
        append <- bitwAnd(fdflags, 1L) != 0
        # FD_WRITE is bit 6. A negative value is "all rights", which some
        # toolchains pass even to read; then only the flags tell intent.
        write_right <- rights >= 0 && bitwAnd(as.integer(rights %% 2^30), 64L) != 0
        exists <- file.exists(p$host)
        isdir <- exists && dir.exists(p$host)
        if (exists && excl && creat) return(wasi_errno[["EXIST"]])
        if (!exists && !creat) return(wasi_errno[["NOENT"]])
        if (want_dir && exists && !isdir) return(wasi_errno[["NOTDIR"]])
        if (isdir) {
          if (trunc) return(wasi_errno[["ISDIR"]])
          wr(m, out, le_u32(new_fd(list(kind = "dir", root = p$root, rel = p$rel))))
          return(0L)
        }
        if (want_dir) return(if (exists) wasi_errno[["NOTDIR"]] else wasi_errno[["NOENT"]])
        # Opening to write in a read-only directory fails here, not at the
        # first write.
        writable <- write_right || trunc || append || (creat && !exists)
        if (writable && !st$writable) return(wasi_errno[["NOTCAPABLE"]])
        writable <- st$writable && (writable || rights < 0)
        if (!exists && !file.create(p$host, showWarnings = FALSE)) return(wasi_errno[["NOENT"]])
        open <- if (writable && trunc) "w+b" else if (writable) "r+b" else "rb"
        con <- tryCatch(file(p$host, open = open), error = function(e) NULL, warning = function(w) NULL)
        if (is.null(con)) return(wasi_errno[["ACCES"]])
        wr(m, out, le_u32(new_fd(list(
          kind = "file", host = p$host, con = con, pos = 0,
          append = append, writable = writable
        ))))
        0L
      }
    ),
    path_readlink = notsup(c("i32", "i32", "i32", "i32", "i32", "i32")),
    path_remove_directory = fn(c("i32", "i32", "i32"), function(fd, ptr, len, caller) {
      if (!is.null(denied())) return(denied())
      p <- resolve(fd, mem(caller), ptr, len)
      if (!is.list(p)) return(p)
      if (!length(p$rel)) return(wasi_errno[["NOTCAPABLE"]])
      if (!file.exists(p$host)) return(wasi_errno[["NOENT"]])
      if (!dir.exists(p$host)) return(wasi_errno[["NOTDIR"]])
      if (length(list.files(p$host, all.files = TRUE, no.. = TRUE))) return(wasi_errno[["NOTEMPTY"]])
      unlink(p$host, recursive = TRUE)
      0L
    }),
    path_rename = fn(c("i32", "i32", "i32", "i32", "i32", "i32"), function(fd, ptr, len, fd2, ptr2, len2, caller) {
      if (!is.null(denied())) return(denied())
      m <- mem(caller)
      from <- resolve(fd, m, ptr, len)
      if (!is.list(from)) return(from)
      to <- resolve(fd2, m, ptr2, len2)
      if (!is.list(to)) return(to)
      if (!file.exists(from$host)) return(wasi_errno[["NOENT"]])
      if (!file.rename(from$host, to$host)) return(wasi_errno[["ACCES"]])
      0L
    }),
    path_symlink = notsup(c("i32", "i32", "i32", "i32", "i32")),
    path_unlink_file = fn(c("i32", "i32", "i32"), function(fd, ptr, len, caller) {
      if (!is.null(denied())) return(denied())
      p <- resolve(fd, mem(caller), ptr, len)
      if (!is.list(p)) return(p)
      if (!file.exists(p$host)) return(wasi_errno[["NOENT"]])
      if (dir.exists(p$host)) return(wasi_errno[["ISDIR"]])
      if (!file.remove(p$host)) return(wasi_errno[["ACCES"]])
      0L
    }),

    poll_oneoff = fn(c("i32", "i32", "i32", "i32"), function(inp, out, nsubs, nevents, caller) {
      if (nsubs == 0) return(wasi_errno[["INVAL"]])
      m <- mem(caller)
      subs <- lapply(seq_len(nsubs) - 1, function(i) {
        base <- inp + 48 * i
        list(
          userdata = wasm_read(m, base, 8, "raw"),
          tag = wasm_read(m, base + 8, 1, "u8"),
          timeout = sum(rd_u32(m, base + 24, 2) * c(1, 2^32)),
          abstime = bitwAnd(wasm_read(m, base + 40, 1, "u16"), 1L) != 0,
          clock = rd_u32(m, base + 16)
        )
      })
      clocks <- Filter(function(s) s$tag == 0, subs)
      ready <- Filter(function(s) s$tag != 0, subs)
      if (!length(ready) && length(clocks)) {
        wait <- vapply(clocks, function(s) {
          if (s$abstime) {
            now <- if (s$clock == 0) as.numeric(Sys.time()) else proc.time()[["elapsed"]] - st$clock0
            max(0, s$timeout / 1e9 - now)
          } else {
            s$timeout / 1e9
          }
        }, 0)
        if (min(wait) > 0) Sys.sleep(min(wait))
        ready <- clocks[wait <= min(wait)]
      }
      events <- unlist(lapply(ready, function(s) {
        c(s$userdata, le_u16(0), as.raw(s$tag), raw(5), le_u64(0), le_u16(0), raw(6))
      }))
      wr(m, out, events)
      wr(m, nevents, le_u32(length(ready)))
      0L
    }),
    proc_exit = wasm_func(function(code, caller) {
      wasi_flush(st)
      st$exit_status <- code
      stop(structure(
        list(message = paste("The program exited with status", code), call = NULL, status = code),
        class = c("nanowasm_wasi_exit", "error", "condition")
      ))
    }, params = "i32"),
    proc_raise = nosys("i32"),
    random_get = fn(c("i32", "i32"), function(buf, len, caller) {
      if (len > 0) wr(mem(caller), buf, as.raw(sample.int(256L, len, replace = TRUE) - 1L))
      0L
    }),
    sched_yield = fn(character(), function(caller) 0L),
    sock_accept = notsup(c("i32", "i32", "i32")),
    sock_recv = notsup(c("i32", "i32", "i32", "i32", "i32", "i32")),
    sock_send = notsup(c("i32", "i32", "i32", "i32", "i32")),
    sock_shutdown = notsup(c("i32", "i32"))
  )
}

# Set a file's modification time from WASI's fst_flags (MTIM = 4, MTIM_NOW = 8);
# access times are left alone.
set_mtime <- function(host, mtim, flags) {
  when <- if (bitwAnd(flags, 8L) != 0) {
    Sys.time()
  } else if (bitwAnd(flags, 4L) != 0) {
    as.POSIXct(mtim / 1e9, origin = "1970-01-01")
  }
  if (!is.null(when) && !isTRUE(Sys.setFileTime(host, when))) {
    return(wasi_errno[["IO"]])
  }
  0L
}
