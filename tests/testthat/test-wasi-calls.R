# Each WASI function, called directly through wasi-probe.wasm (which
# re-exports them unchanged), checked for its result code and its effect.
# Memory layout used here: out-parameters at 0, iovecs at 100, paths at 1000,
# data at 2000.

errno <- c(
  SUCCESS = 0L, BADF = 8L, EXIST = 20L, FAULT = 21L, INVAL = 28L,
  ISDIR = 31L, NOENT = 44L, NOSYS = 52L, NOTDIR = 54L, NOTEMPTY = 55L,
  NOTSUP = 58L, SPIPE = 70L, NOTCAPABLE = 76L
)
READ <- 2
WRITE <- 64
CREAT <- 1L
DIRECTORY <- 2L
EXCL <- 4L
TRUNC <- 8L
APPEND <- 1L

probe <- function(dirs = character(), writable = TRUE, ...) {
  wasi <- wasm_wasi(dirs = dirs, writable = writable, stdout = "capture", stderr = "capture", ...)
  inst <- wasm_instantiate(wasm_module(fixture("wasi-probe")), wasi = wasi)
  list(inst = inst, mem = wasm_memory(inst), wasi = wasi)
}

# Write a path at 1000; returns its pointer and length.
path_at <- function(p, path, at = 1000L) {
  wasm_write_string(p$mem, at, path, nul = FALSE)
  c(at, length(charToRaw(enc2utf8(path))))
}

open_at <- function(p, path, oflags = 0L, rights = READ + WRITE, fdflags = 0L, dirfd = 3L) {
  a <- path_at(p, path)
  res <- p$inst$path_open(dirfd, 0L, a[[1]], a[[2]], oflags, rights, 0, fdflags, 0L)
  list(errno = res, fd = if (res == 0L) as.integer(wasm_read(p$mem, 0, 1, "u32")))
}

# One iovec at 100 over `bytes` written at 2000 (or `n` bytes of space).
iov <- function(p, bytes = NULL, n = length(bytes)) {
  if (!is.null(bytes)) wasm_write(p$mem, 2000, bytes, "raw")
  wasm_write(p$mem, 100, c(2000, n), "u32")
  100L
}

write_fd <- function(p, fd, text) {
  res <- p$inst$fd_write(fd, iov(p, charToRaw(text)), 1L, 0L)
  list(errno = res, n = wasm_read(p$mem, 0, 1, "u32"))
}

read_fd <- function(p, fd, n = 100) {
  res <- p$inst$fd_read(fd, iov(p, n = n), 1L, 0L)
  got <- wasm_read(p$mem, 0, 1, "u32")
  list(errno = res, text = rawToChar(wasm_read(p$mem, 2000, got, "raw")))
}

test_that("files are written, read, seeked and closed", {
  dir <- withr_tempdir()
  p <- probe(dir)
  f <- open_at(p, "a.txt", CREAT)
  expect_identical(f$errno, errno[["SUCCESS"]])
  expect_identical(write_fd(p, f$fd, "hello world"), list(errno = 0L, n = 11))
  expect_identical(p$inst$fd_tell(f$fd, 0L), 0L)
  expect_identical(wasm_read(p$mem, 0, 1, "u64"), 11)

  expect_identical(p$inst$fd_seek(f$fd, 6, 0L, 0L), 0L)
  expect_identical(read_fd(p, f$fd), list(errno = 0L, text = "world"))
  expect_identical(p$inst$fd_seek(f$fd, -5, 1L, 0L), 0L)
  expect_identical(wasm_read(p$mem, 0, 1, "u64"), 6)
  expect_identical(p$inst$fd_seek(f$fd, -1, 2L, 0L), 0L)
  expect_identical(wasm_read(p$mem, 0, 1, "u64"), 10)
  expect_identical(p$inst$fd_seek(f$fd, -100, 0L, 0L), errno[["INVAL"]])
  expect_identical(p$inst$fd_seek(f$fd, 0, 9L, 0L), errno[["INVAL"]])

  # pread/pwrite use an offset and leave the position alone.
  expect_identical(p$inst$fd_pwrite(f$fd, iov(p, charToRaw("W")), 1L, 6, 0L), 0L)
  expect_identical(p$inst$fd_pread(f$fd, iov(p, n = 5), 1L, 6, 0L), 0L)
  expect_identical(rawToChar(wasm_read(p$mem, 2000, 5, "raw")), "World")
  p$inst$fd_tell(f$fd, 0L)
  expect_identical(wasm_read(p$mem, 0, 1, "u64"), 10)

  expect_identical(p$inst$fd_sync(f$fd), 0L)
  expect_identical(p$inst$fd_datasync(f$fd), 0L)
  expect_identical(p$inst$fd_advise(f$fd, 0, 0, 0L), 0L)
  expect_identical(p$inst$fd_allocate(f$fd, 0, 10), errno[["NOTSUP"]])
  expect_identical(p$inst$fd_fdstat_set_rights(f$fd, 0, 0), 0L)
  expect_identical(p$inst$fd_close(f$fd), 0L)
  expect_identical(readLines(file.path(dir, "a.txt"), warn = FALSE), "hello World")

  for (call in list(
    function(fd) p$inst$fd_close(fd), function(fd) p$inst$fd_tell(fd, 0L),
    function(fd) p$inst$fd_sync(fd), function(fd) p$inst$fd_datasync(fd),
    function(fd) p$inst$fd_seek(fd, 0, 0L, 0L), function(fd) p$inst$fd_advise(fd, 0, 0, 0L),
    function(fd) p$inst$fd_fdstat_get(fd, 0L), function(fd) p$inst$fd_filestat_get(fd, 0L),
    function(fd) p$inst$fd_fdstat_set_flags(fd, 0L), function(fd) p$inst$fd_fdstat_set_rights(fd, 0, 0),
    function(fd) p$inst$fd_read(fd, iov(p, n = 1), 1L, 0L), function(fd) p$inst$fd_write(fd, iov(p, as.raw(1)), 1L, 0L),
    function(fd) p$inst$fd_pread(fd, iov(p, n = 1), 1L, 0, 0L), function(fd) p$inst$fd_pwrite(fd, iov(p, as.raw(1)), 1L, 0, 0L),
    function(fd) p$inst$fd_readdir(fd, 2000L, 100L, 0, 0L), function(fd) p$inst$fd_filestat_set_size(fd, 0),
    function(fd) p$inst$fd_filestat_set_times(fd, 0, 0, 0L), function(fd) p$inst$fd_prestat_get(fd, 0L),
    function(fd) p$inst$fd_prestat_dir_name(fd, 0L, 10L)
  )) {
    expect_identical(call(f$fd), errno[["BADF"]])
  }
})

test_that("append mode writes at the end and can be switched off", {
  dir <- withr_tempdir()
  write_lines_lf("start", file.path(dir, "log.txt"))
  p <- probe(dir)
  f <- open_at(p, "log.txt", fdflags = APPEND)
  expect_identical(p$inst$fd_fdstat_get(f$fd, 0L), 0L)
  expect_identical(wasm_read(p$mem, 2, 1, "u16"), 1L)
  write_fd(p, f$fd, "more\n")
  expect_identical(p$inst$fd_fdstat_set_flags(f$fd, 0L), 0L)
  p$inst$fd_seek(f$fd, 0, 0L, 0L)
  write_fd(p, f$fd, "S")
  p$inst$fd_close(f$fd)
  expect_identical(readLines(file.path(dir, "log.txt")), c("Start", "more"))
})

test_that("descriptors report their type, and stdio can't seek", {
  dir <- withr_tempdir()
  write_lines_lf("x", file.path(dir, "f"))
  p <- probe(dir)
  type <- function(fd) {
    expect_identical(p$inst$fd_fdstat_get(fd, 0L), 0L)
    wasm_read(p$mem, 0, 1, "u8")
  }
  expect_identical(c(type(0L), type(1L), type(2L), type(3L)), c(2L, 2L, 2L, 3L))
  f <- open_at(p, "f", rights = READ)
  expect_identical(type(f$fd), 4L)
  expect_identical(p$inst$fd_fdstat_set_flags(0L, 1L), 0L)

  expect_identical(p$inst$fd_filestat_get(1L, 0L), 0L)
  expect_identical(wasm_read(p$mem, 16, 1, "u8"), 2L)
  expect_identical(p$inst$fd_filestat_get(3L, 0L), 0L)
  expect_identical(wasm_read(p$mem, 16, 1, "u8"), 3L)
  expect_identical(p$inst$fd_filestat_get(f$fd, 0L), 0L)
  expect_identical(wasm_read(p$mem, 16, 1, "u8"), 4L)
  expect_identical(wasm_read(p$mem, 32, 1, "u64"), file.size(file.path(dir, "f")))

  expect_identical(p$inst$fd_seek(1L, 0, 0L, 0L), errno[["SPIPE"]])
  expect_identical(p$inst$fd_tell(0L, 0L), errno[["SPIPE"]])
  expect_identical(p$inst$fd_seek(3L, 0, 0L, 0L), errno[["BADF"]])
  expect_identical(p$inst$fd_pread(0L, iov(p, n = 1), 1L, 0, 0L), errno[["SPIPE"]])
  expect_identical(p$inst$fd_pread(3L, iov(p, n = 1), 1L, 0, 0L), errno[["ISDIR"]])
  expect_identical(p$inst$fd_pwrite(1L, iov(p, as.raw(1)), 1L, 0, 0L), errno[["SPIPE"]])
  expect_identical(p$inst$fd_pwrite(3L, iov(p, as.raw(1)), 1L, 0, 0L), errno[["ISDIR"]])
  expect_identical(p$inst$fd_read(3L, iov(p, n = 1), 1L, 0L), errno[["ISDIR"]])
  expect_identical(p$inst$fd_read(1L, iov(p, n = 1), 1L, 0L), errno[["BADF"]])
  expect_identical(p$inst$fd_write(3L, iov(p, as.raw(1)), 1L, 0L), errno[["ISDIR"]])
  expect_identical(p$inst$fd_write(0L, iov(p, as.raw(1)), 1L, 0L), errno[["BADF"]])
  expect_identical(p$inst$fd_readdir(f$fd, 2000L, 100L, 0, 0L), errno[["NOTDIR"]])
  expect_identical(p$inst$fd_filestat_set_size(3L, 0), errno[["INVAL"]])
  expect_identical(p$inst$fd_filestat_set_times(3L, 0, 0, 4L), 0L)
})

test_that("read-only descriptors can't be written", {
  dir <- withr_tempdir()
  write_lines_lf("x", file.path(dir, "f"))
  p <- probe(dir)
  f <- open_at(p, "f", rights = READ)
  expect_identical(write_fd(p, f$fd, "y")$errno, errno[["NOTCAPABLE"]])
  expect_identical(p$inst$fd_pwrite(f$fd, iov(p, as.raw(1)), 1L, 0, 0L), errno[["NOTCAPABLE"]])
  expect_identical(p$inst$fd_filestat_set_size(f$fd, 0), errno[["NOTCAPABLE"]])
  expect_identical(p$inst$fd_filestat_set_times(f$fd, 0, 0, 8L), errno[["NOTCAPABLE"]])
  expect_identical(read_fd(p, f$fd), list(errno = 0L, text = "x\n"))
})

test_that("files grow, shrink and get modification times", {
  dir <- withr_tempdir()
  p <- probe(dir)
  f <- open_at(p, "f", CREAT)
  write_fd(p, f$fd, "abcdef")
  expect_identical(p$inst$fd_filestat_set_size(f$fd, 3), 0L)
  expect_identical(file.size(file.path(dir, "f")), 3)
  expect_identical(p$inst$fd_filestat_set_size(f$fd, 8), 0L)
  expect_identical(readBin(file.path(dir, "f"), "raw", 8), c(charToRaw("abc"), raw(5)))

  # From R, an i64 argument must stay within 2^53 ns (early 1970); the
  # files test sets a real timestamp from C.
  when <- 1e6
  if (.Platform$OS.type != "windows") {
    # Windows doesn't set times this early; a real one is set from C in
    # test-wasi.R.
    expect_identical(p$inst$fd_filestat_set_times(f$fd, 0, when * 1e9, 4L), 0L)
    expect_equal(as.numeric(file.mtime(file.path(dir, "f"))), when, tolerance = 1)
  }
  a <- path_at(p, "f")
  expect_identical(p$inst$path_filestat_set_times(3L, 0L, a[[1]], a[[2]], 0, 0, 8L), 0L)
  expect_lt(abs(as.numeric(file.mtime(file.path(dir, "f"))) - as.numeric(Sys.time())), 60)
  expect_identical(p$inst$fd_filestat_set_times(f$fd, 0, 0, 0L), 0L)
  # The descriptor still works after its connection was reopened.
  p$inst$fd_seek(f$fd, 0, 0L, 0L)
  expect_identical(write_fd(p, f$fd, "ABC")$errno, 0L)
  expect_identical(readBin(file.path(dir, "f"), "raw", 8), c(charToRaw("ABC"), raw(5)))

  b <- path_at(p, "missing")
  expect_identical(p$inst$path_filestat_set_times(3L, 0L, b[[1]], b[[2]], 0, 0, 8L), errno[["NOENT"]])
  ro <- probe(dir, writable = FALSE)
  a <- path_at(ro, "f")
  expect_identical(ro$inst$path_filestat_set_times(3L, 0L, a[[1]], a[[2]], 0, 0, 8L), errno[["NOTCAPABLE"]])
})

test_that("path_open follows its flags", {
  dir <- withr_tempdir()
  write_lines_lf("x", file.path(dir, "f"))
  dir.create(file.path(dir, "d"))
  p <- probe(dir)
  expect_identical(open_at(p, "f", CREAT + EXCL)$errno, errno[["EXIST"]])
  expect_identical(open_at(p, "f", DIRECTORY)$errno, errno[["NOTDIR"]])
  expect_identical(open_at(p, "d", TRUNC)$errno, errno[["ISDIR"]])
  expect_identical(open_at(p, "missing")$errno, errno[["NOENT"]])
  expect_identical(open_at(p, "missing", DIRECTORY)$errno, errno[["NOENT"]])
  expect_identical(open_at(p, "new", CREAT + DIRECTORY)$errno, errno[["NOENT"]])
  expect_identical(open_at(p, "f", dirfd = 9L)$errno, errno[["BADF"]])
  f <- open_at(p, "f", rights = READ)
  expect_identical(open_at(p, "x", dirfd = f$fd)$errno, errno[["NOTDIR"]])
  expect_identical(open_at(p, "/f")$errno, errno[["NOTCAPABLE"]])
  expect_identical(open_at(p, "d\\..\\f")$errno, errno[["NOTCAPABLE"]])
  expect_identical(open_at(p, "C:/f")$errno, errno[["NOTCAPABLE"]])

  d <- open_at(p, "d", DIRECTORY)
  expect_identical(d$errno, 0L)
  sub <- open_at(p, "inner.txt", CREAT, dirfd = d$fd)
  expect_identical(sub$errno, 0L)
  expect_true(file.exists(file.path(dir, "d", "inner.txt")))
  expect_identical(open_at(p, "../f", rights = READ, dirfd = d$fd)$errno, 0L)
  expect_identical(open_at(p, "../../f", dirfd = d$fd)$errno, errno[["NOTCAPABLE"]])

  # TRUNC empties an existing file; "all rights" alone isn't write intent.
  t <- open_at(p, "f", TRUNC)
  expect_identical(file.size(file.path(dir, "f")), 0)
  ro <- probe(dir, writable = FALSE)
  expect_identical(open_at(ro, "f", rights = -1)$errno, 0L)
  expect_identical(open_at(ro, "f", rights = READ + WRITE)$errno, errno[["NOTCAPABLE"]])
})

test_that("directories are listed in pieces with cookies", {
  dir <- withr_tempdir()
  for (f in c("a", "bb", "ccc")) write_lines_lf("x", file.path(dir, f))
  p <- probe(dir)
  entries <- function(cookie, size) {
    expect_identical(p$inst$fd_readdir(3L, 2000L, size, cookie, 0L), 0L)
    used <- wasm_read(p$mem, 0, 1, "u32")
    bytes <- wasm_read(p$mem, 2000, used, "raw")
    out <- list()
    pos <- 0
    while (pos + 24 <= used) {
      namlen <- readBin(bytes[pos + 17:20], "integer", size = 4, endian = "little")
      if (pos + 24 + namlen > used) break
      out[[length(out) + 1]] <- list(
        next_cookie = readBin(bytes[pos + 1:4], "integer", size = 4, endian = "little"),
        name = rawToChar(bytes[pos + 24 + seq_len(namlen)]),
        type = as.integer(bytes[[pos + 21]])
      )
      pos <- pos + 24 + namlen
    }
    list(used = used, entries = out)
  }
  all <- entries(0, 1000)
  expect_identical(vapply(all$entries, `[[`, "", "name"), c(".", "..", "a", "bb", "ccc"))
  expect_identical(vapply(all$entries, `[[`, 1L, "type"), c(3L, 3L, 4L, 4L, 4L))
  # A buffer that ends mid-entry is filled completely, so the caller knows
  # to ask again from the last whole entry's cookie.
  part <- entries(0, 60)
  expect_identical(part$used, 60)
  expect_identical(vapply(part$entries, `[[`, "", "name"), c(".", ".."))
  rest <- entries(part$entries[[2]]$next_cookie, 1000)
  expect_identical(vapply(rest$entries, `[[`, "", "name"), c("a", "bb", "ccc"))
  expect_identical(entries(5, 1000)$used, 0)
})

test_that("preopened directories are described and can be closed or renumbered", {
  dir <- withr_tempdir()
  p <- probe(c("/data" = dir))
  expect_identical(p$inst$fd_prestat_get(3L, 0L), 0L)
  expect_identical(wasm_read(p$mem, 0, 1, "u8"), 0L)
  expect_identical(wasm_read(p$mem, 4, 1, "u32"), 5)
  expect_identical(p$inst$fd_prestat_dir_name(3L, 2000L, 5L), 0L)
  expect_identical(rawToChar(wasm_read(p$mem, 2000, 5, "raw")), "/data")
  expect_identical(p$inst$fd_prestat_dir_name(3L, 2000L, 2L), errno[["INVAL"]])
  expect_identical(p$inst$fd_prestat_get(0L, 0L), errno[["BADF"]])
  expect_identical(p$inst$fd_prestat_get(4L, 0L), errno[["BADF"]])

  f <- open_at(p, "f", CREAT)
  expect_identical(p$inst$fd_renumber(f$fd, 0L), 0L)
  expect_identical(write_fd(p, 0L, "via 0")$errno, 0L)
  expect_identical(p$inst$fd_tell(f$fd, 0L), errno[["BADF"]])
  expect_identical(p$inst$fd_renumber(0L, 0L), 0L)
  expect_identical(p$inst$fd_renumber(0L, 9L), errno[["BADF"]])
  expect_identical(p$inst$fd_close(3L), 0L)
  expect_identical(p$inst$fd_prestat_get(3L, 0L), errno[["BADF"]])
  expect_identical(readLines(file.path(dir, "f"), warn = FALSE), "via 0")
})

test_that("directory and file paths are created, renamed and removed", {
  dir <- withr_tempdir()
  other <- withr_tempdir()
  p <- probe(c("/a" = dir, "/b" = other))
  a <- path_at(p, "d", 1200L)
  expect_identical(p$inst$path_create_directory(3L, a[[1]], a[[2]]), 0L)
  expect_identical(p$inst$path_create_directory(3L, a[[1]], a[[2]]), errno[["EXIST"]])
  write_lines_lf("x", file.path(dir, "d", "f"))
  expect_identical(p$inst$path_remove_directory(3L, a[[1]], a[[2]]), errno[["NOTEMPTY"]])
  expect_identical(p$inst$path_unlink_file(3L, a[[1]], a[[2]]), errno[["ISDIR"]])

  dot <- path_at(p, ".")
  expect_identical(p$inst$path_remove_directory(3L, dot[[1]], dot[[2]]), errno[["NOTCAPABLE"]])

  # Rename across the two preopened directories.
  from <- path_at(p, "d/f", 1000L)
  to <- path_at(p, "g", 1100L)
  expect_identical(p$inst$path_rename(3L, from[[1]], from[[2]], 4L, to[[1]], to[[2]]), 0L)
  expect_true(file.exists(file.path(other, "g")))
  expect_identical(p$inst$path_rename(3L, from[[1]], from[[2]], 4L, to[[1]], to[[2]]), errno[["NOENT"]])
  expect_identical(p$inst$path_rename(3L, from[[1]], from[[2]], 9L, to[[1]], to[[2]]), errno[["BADF"]])
  up <- path_at(p, "../x", 1100L)
  expect_identical(p$inst$path_rename(3L, from[[1]], from[[2]], 4L, up[[1]], up[[2]]), errno[["NOTCAPABLE"]])
  expect_identical(p$inst$path_rename(9L, from[[1]], from[[2]], 4L, to[[1]], to[[2]]), errno[["BADF"]])

  g <- path_at(p, "g")
  expect_identical(p$inst$path_filestat_get(4L, 0L, g[[1]], g[[2]], 2000L), 0L)
  expect_identical(wasm_read(p$mem, 2016, 1, "u8"), 4L)
  expect_identical(p$inst$path_unlink_file(4L, g[[1]], g[[2]]), 0L)
  expect_identical(p$inst$path_unlink_file(4L, g[[1]], g[[2]]), errno[["NOENT"]])
  expect_identical(p$inst$path_filestat_get(4L, 0L, g[[1]], g[[2]], 2000L), errno[["NOENT"]])
  expect_identical(p$inst$path_remove_directory(3L, a[[1]], a[[2]]), 0L)
  expect_identical(p$inst$path_remove_directory(3L, a[[1]], a[[2]]), errno[["NOENT"]])
  write_lines_lf("x", file.path(dir, "file"))
  file <- path_at(p, "file", 1300L)
  expect_identical(p$inst$path_remove_directory(3L, file[[1]], file[[2]]), errno[["NOTDIR"]])
  bad <- path_at(p, "/abs")
  expect_identical(p$inst$path_create_directory(3L, bad[[1]], bad[[2]]), errno[["NOTCAPABLE"]])
  expect_identical(p$inst$path_unlink_file(3L, bad[[1]], bad[[2]]), errno[["NOTCAPABLE"]])
  expect_identical(p$inst$path_filestat_get(3L, 0L, bad[[1]], bad[[2]], 2000L), errno[["NOTCAPABLE"]])
  expect_identical(p$inst$path_filestat_set_times(3L, 0L, bad[[1]], bad[[2]], 0, 0, 8L), errno[["NOTCAPABLE"]])

  ro <- probe(dir, writable = FALSE)
  a <- path_at(ro, "d", 1200L)
  for (call in list(
    function() ro$inst$path_create_directory(3L, a[[1]], a[[2]]),
    function() ro$inst$path_remove_directory(3L, a[[1]], a[[2]]),
    function() ro$inst$path_unlink_file(3L, a[[1]], a[[2]]),
    function() ro$inst$path_rename(3L, a[[1]], a[[2]], 3L, a[[1]], a[[2]])
  )) {
    expect_identical(call(), errno[["NOTCAPABLE"]])
  }
})

test_that("links, sockets and signals are not supported", {
  p <- probe()
  expect_identical(p$inst$path_link(3L, 0L, 0L, 0L, 3L, 0L, 0L), errno[["NOTSUP"]])
  expect_identical(p$inst$path_symlink(0L, 0L, 3L, 0L, 0L), errno[["NOTSUP"]])
  expect_identical(p$inst$path_readlink(3L, 0L, 0L, 0L, 0L, 0L), errno[["NOTSUP"]])
  expect_identical(p$inst$sock_accept(3L, 0L, 0L), errno[["NOTSUP"]])
  expect_identical(p$inst$sock_recv(3L, 0L, 0L, 0L, 0L, 0L), errno[["NOTSUP"]])
  expect_identical(p$inst$sock_send(3L, 0L, 0L, 0L, 0L), errno[["NOTSUP"]])
  expect_identical(p$inst$sock_shutdown(3L, 0L), errno[["NOTSUP"]])
  expect_identical(p$inst$proc_raise(2L), errno[["NOSYS"]])
  expect_identical(p$inst$sched_yield(), 0L)
})

test_that("arguments and environment are laid out as C expects", {
  p <- probe(args = c("a", "bc"), env = c(K = "v"), program = "prog")
  expect_identical(p$inst$args_sizes_get(0L, 4L), 0L)
  expect_identical(wasm_read(p$mem, 0, 2, "u32"), c(3, 10))
  expect_identical(p$inst$args_get(100L, 2000L), 0L)
  ptrs <- wasm_read(p$mem, 100, 3, "u32")
  expect_identical(ptrs, c(2000, 2005, 2007))
  expect_identical(vapply(ptrs, function(x) wasm_read_string(p$mem, x), ""), c("prog", "a", "bc"))
  expect_identical(p$inst$environ_sizes_get(0L, 4L), 0L)
  expect_identical(wasm_read(p$mem, 0, 2, "u32"), c(1, 4))
  expect_identical(p$inst$environ_get(100L, 2000L), 0L)
  expect_identical(wasm_read_string(p$mem, 2000), "K=v")

  empty <- probe()
  expect_identical(empty$inst$environ_sizes_get(0L, 4L), 0L)
  expect_identical(wasm_read(empty$mem, 0, 2, "u32"), c(0, 0))
  expect_identical(empty$inst$environ_get(100L, 2000L), 0L)
})

test_that("clocks know their ids", {
  p <- probe()
  for (id in 0:3) {
    expect_identical(p$inst$clock_res_get(id, 0L), 0L)
    expect_identical(p$inst$clock_time_get(id, 0, 0L), 0L)
  }
  expect_identical(p$inst$clock_res_get(9L, 0L), errno[["INVAL"]])
  expect_identical(p$inst$clock_time_get(9L, 0, 0L), errno[["INVAL"]])
  p$inst$clock_time_get(0L, 0, 0L)
  ns <- sum(wasm_read(p$mem, 0, 2, "u32") * c(1, 2^32))
  expect_lt(abs(ns / 1e9 - as.numeric(Sys.time())), 60)
})

test_that("poll_oneoff sleeps on clocks and reports stdio ready", {
  p <- probe()
  subscription <- function(at, userdata, tag, timeout_ns = 0, flags = 0L, clock = 1L) {
    wasm_write(p$mem, at, raw(48), "raw")
    wasm_write(p$mem, at, c(userdata, 0), "u32")
    wasm_write(p$mem, at + 8, tag, "u8")
    wasm_write(p$mem, at + 16, clock, "u32")
    wasm_write(p$mem, at + 24, timeout_ns, "u64")
    wasm_write(p$mem, at + 40, flags, "u16")
  }
  expect_identical(p$inst$poll_oneoff(2000L, 3000L, 0L, 0L), errno[["INVAL"]])

  subscription(2000, 7, 0L, timeout_ns = 50e6)
  elapsed <- system.time(res <- p$inst$poll_oneoff(2000L, 3000L, 1L, 0L))[["elapsed"]]
  expect_identical(res, 0L)
  expect_gte(elapsed, 0.04)
  expect_identical(wasm_read(p$mem, 0, 1, "u32"), 1)
  expect_identical(wasm_read(p$mem, 3000, 1, "u32"), 7)

  # An fd subscription is ready at once, without waiting on the clock.
  subscription(2000, 1, 0L, timeout_ns = 10e9)
  subscription(2048, 2, 1L)
  elapsed <- system.time(p$inst$poll_oneoff(2000L, 3000L, 2L, 0L))[["elapsed"]]
  expect_lt(elapsed, 5)
  expect_identical(wasm_read(p$mem, 3000, 1, "u32"), 2)
  expect_identical(wasm_read(p$mem, 3010, 1, "u8"), 1L)

  # An absolute deadline in the past doesn't sleep.
  subscription(2000, 3, 0L, timeout_ns = 1e9, flags = 1L, clock = 0L)
  expect_lt(system.time(p$inst$poll_oneoff(2000L, 3000L, 1L, 0L))[["elapsed"]], 5)
  subscription(2000, 4, 0L, timeout_ns = 1e9, flags = 1L, clock = 1L)
  expect_lt(system.time(p$inst$poll_oneoff(2000L, 3000L, 1L, 0L))[["elapsed"]], 5)
})

test_that("memory outside the module is EFAULT", {
  p <- probe()
  expect_identical(p$inst$args_sizes_get(70000L, 0L), errno[["FAULT"]])
  expect_identical(p$inst$clock_time_get(0L, 0, 70000L), errno[["FAULT"]])
  expect_identical(p$inst$random_get(65530L, 100L), errno[["FAULT"]])
  expect_identical(p$inst$random_get(0L, 0L), 0L)
})
