wasi_fixture <- function(name) test_path("fixtures", "wasi", paste0(name, ".wasm"))
example <- function(name) system.file("extdata", name, package = "nanowasm")

test_that("wasm_run() runs a program and captures its output", {
  res <- wasm_run(example("hello-wasi.wasm"), args = c("from", "R"), env = c(GREETING = "Hi"))
  expect_s3_class(res, "nanowasm_run")
  expect_identical(res$status, 0L)
  expect_identical(res$stdout, "Hi from R!\n")
  expect_identical(res$stderr, "")
  expect_snapshot(print(res))
})

test_that("output can go to the console or nowhere", {
  hello <- example("hello-wasi.wasm")
  expect_output(res <- wasm_run(hello, stdout = "console"), "Hello!")
  expect_null(res$stdout)
  expect_silent(res <- wasm_run(hello, stdout = "discard"))
  expect_null(res$stdout)
  expect_output(
    wasm_run(wasi_fixture("stdio"), stdin = "x", stdout = "console", stderr = "discard"),
    "X\né"
  )
})

test_that("programs see their arguments and environment, and exit with a status", {
  res <- wasm_run(wasi_fixture("args"), args = c("7", "x y"), env = c(A = "1", B = "two"), program = "prog")
  expect_identical(res$status, 7L)
  expect_identical(
    res$stdout,
    "argc=3\nargv[0]=prog\nargv[1]=7\nargv[2]=x y\nenv A=1\nenv B=two\n"
  )
  expect_identical(wasm_run(wasi_fixture("args"))$status, 0L)
  expect_match(wasm_run(wasi_fixture("args"), args = "été")$stdout, "argv\\[1\\]=été")
})

test_that("stdin comes from a character or raw vector", {
  res <- wasm_run(wasi_fixture("stdio"), stdin = c("hello", "wörld"))
  expect_identical(res$stdout, "HELLO\nWöRLD\né\n")
  expect_identical(res$stderr, "read 13 bytes\n")
  expect_identical(wasm_run(wasi_fixture("stdio"), stdin = charToRaw("ab"))$stdout, "ABé\n")
  expect_identical(wasm_run(wasi_fixture("stdio"))$stderr, "read 0 bytes\n")
})

test_that("clocks, sleeping and randomness work, reproducibly", {
  res <- wasm_run(wasi_fixture("clock"))
  lines <- strsplit(res$stdout, "\n")[[1]]
  realtime <- as.numeric(sub("realtime ", "", lines[[1]]))
  expect_lt(abs(realtime - as.numeric(Sys.time())), 60)
  expect_identical(lines[[2]], "resolution 1000")
  expect_gte(as.numeric(sub("slept ", "", lines[[3]])), 45)
  set.seed(42)
  a <- wasm_run(wasi_fixture("clock"))$stdout
  set.seed(42)
  b <- wasm_run(wasi_fixture("clock"))$stdout
  expect_identical(sub(".*random", "", a), sub(".*random", "", b))
})

files <- function(..., dirs, writable = TRUE) {
  wasm_run(wasi_fixture("files"), args = c(...), dirs = dirs, writable = writable)
}

test_that("programs read and write files in a granted directory", {
  dir <- withr_tempdir()
  res <- files(
    "write", "a.txt", "hello", "append", "a.txt", " world", "read", "a.txt",
    "readat", "a.txt", "6", "stat", "a.txt",
    dirs = dir
  )
  expect_identical(res$status, 0L)
  expect_identical(
    res$stdout,
    "wrote 5\nwrote 6\nread \"hello world\"\nread \"world\"\nstat file 11\n"
  )
  expect_identical(readLines(file.path(dir, "a.txt"), warn = FALSE), "hello world")

  res <- files(
    "mkdir", "sub", "write", "sub/b.txt", "x", "ls", ".", "mv", "a.txt", "sub/c.txt",
    "ls", "sub", "stat", "sub", "truncate", "sub/c.txt", "3", "read", "sub/c.txt",
    dirs = dir
  )
  expect_identical(
    res$stdout,
    paste0(
      "mkdir ok\nwrote 1\nls: a.txt sub\nmv ok\nls: b.txt c.txt\nstat dir ",
      file.info(file.path(dir, "sub"))$size, "\ntruncate ok\nread \"hel\"\n"
    )
  )

  res <- files("truncate", "sub/c.txt", "5", "stat", "sub/c.txt", "rm", "sub/b.txt",
               "rmdir", "sub", "rm", "sub/c.txt", "rmdir", "sub", "ls", ".", dirs = dir)
  expect_identical(
    res$stdout,
    "truncate ok\nstat file 5\nrm ok\nrmdir: errno 55\nrm ok\nrmdir ok\nls:\n"
  )
  expect_identical(res$status, 1L)
})

test_that("file errors are WASI errnos", {
  dir <- withr_tempdir()
  res <- files("read", "missing.txt", "rm", "missing.txt", "rmdir", "missing",
               "stat", "missing", "mv", "missing", "x", dirs = dir)
  expect_identical(
    res$stdout,
    "open: errno 44\nrm: errno 44\nrmdir: errno 44\nstat: errno 44\nmv: errno 44\n"
  )
  writeLines("x", file.path(dir, "f"))
  res <- files("mkdir", "f", "rm", ".", "rmdir", "f", "ls", "f", dirs = dir)
  expect_identical(res$stdout, "mkdir: errno 20\nrm: errno 31\nrmdir: errno 54\nopendir: errno 54\n")
})

test_that("directories are read-only unless writable = TRUE", {
  dir <- withr_tempdir()
  writeLines("data", file.path(dir, "in.txt"))
  res <- files("read", "in.txt", "write", "out.txt", "no", "append", "in.txt", "x",
               "mkdir", "d", "rm", "in.txt", "mv", "in.txt", "x.txt", "truncate", "in.txt", "0",
               dirs = dir, writable = FALSE)
  expect_identical(
    res$stdout,
    paste0(
      "read \"data\n\"\nopen: errno 76\nopen: errno 76\nmkdir: errno 76\n",
      "rm: errno 76\nmv: errno 76\ntruncate: errno 76\n"
    )
  )
  expect_identical(list.files(dir), "in.txt")
  expect_identical(readLines(file.path(dir, "in.txt")), "data")
})

test_that("paths can't leave a granted directory", {
  root <- withr_tempdir()
  dir <- file.path(root, "box")
  dir.create(dir)
  writeLines("secret", file.path(root, "outside.txt"))
  res <- files("read", "../outside.txt", "read", "/etc/passwd", "read", "a/../../outside.txt",
               "rmdir", "..", "rm", "../outside.txt", "stat", "..", dirs = dir)
  expect_identical(
    res$stdout,
    paste0(
      "open: errno 76\nopen: errno 44\nopen: errno 76\nrmdir: errno 76\n",
      "rm: errno 76\nstat: errno 76\n"
    )
  )
  expect_true(file.exists(file.path(root, "outside.txt")))
})

test_that("symbolic links can't lead outside a granted directory", {
  skip_on_os("windows")
  root <- withr_tempdir()
  dir <- file.path(root, "box")
  dir.create(dir)
  writeLines("secret", file.path(root, "outside.txt"))
  file.symlink(file.path(root, "outside.txt"), file.path(dir, "link.txt"))
  file.symlink(root, file.path(dir, "up"))
  res <- files("read", "link.txt", "read", "up/outside.txt", dirs = dir)
  expect_identical(res$stdout, "open: errno 76\nopen: errno 76\n")
})

test_that("several directories are seen at their names", {
  input <- withr_tempdir()
  output <- withr_tempdir()
  writeLines("data", file.path(input, "in.txt"))
  res <- files("read", "/in/in.txt", "write", "/out/o.txt", "ok", "ls", "/out",
               dirs = c("/in" = input, "/out" = output))
  expect_identical(res$stdout, "read \"data\n\"\nwrote 2\nls: o.txt\n")
  expect_identical(list.files(output), "o.txt")
})

test_that("the cat example reads files and stdin", {
  dir <- withr_tempdir()
  writeLines(c("a,b", "1,2"), file.path(dir, "data.csv"))
  cat_wasm <- example("cat-wasi.wasm")
  expect_identical(wasm_run(cat_wasm, args = "data.csv", dirs = dir)$stdout, "a,b\n1,2\n")
  expect_identical(wasm_run(cat_wasm, stdin = "piped")$stdout, "piped\n")
  res <- wasm_run(cat_wasm, args = "nope.csv", dirs = dir)
  expect_identical(res$status, 1L)
  expect_match(res$stderr, "^cat: nope.csv: ")
})

test_that("reactors are initialised and can call WASI directly", {
  mod <- wasm_module(test_path("fixtures", "wasi-reactor.wasm"))
  wasi <- wasm_wasi(stdout = "capture", stderr = "capture")
  inst <- wasm_instantiate(mod, wasi = wasi)
  expect_identical(wasm_global(inst, "ready"), 1L)
  expect_identical(inst$say(1L), 0L)
  expect_identical(inst$say(2L), 0L)
  expect_identical(wasm_wasi_output(wasi), "reactor says hi\n")
  expect_identical(wasm_wasi_output(wasi, "stderr"), "reactor says hi\n")
  expect_identical(inst$say(0L), 8L)
  expect_identical(inst$say(9L), 8L)
  expect_identical(inst$bad_write(), 21L)
  expect_identical(inst$random(16L), 0L)
  expect_error(wasm_wasi_start(inst), "not a WASI command")
})

test_that("imports can replace WASI functions", {
  mod <- wasm_module(test_path("fixtures", "wasi-reactor.wasm"))
  seen <- NULL
  own <- wasm_func(function(buf, len) {
    seen <<- len
    0L
  }, c("i32", "i32"), "i32")
  inst <- wasm_instantiate(
    mod,
    imports = list(wasi_snapshot_preview1 = list(random_get = own)),
    wasi = wasm_wasi()
  )
  expect_identical(inst$random(5L), 0L)
  expect_identical(seen, 5L)
})

test_that("WASI environments are checked and belong to one instance", {
  expect_error(wasm_wasi(args = 1), class = "nanowasm_argument_error")
  expect_error(wasm_wasi(env = "A=1"), "named character vector")
  expect_error(wasm_wasi(stdin = 1), class = "nanowasm_argument_error")
  expect_error(wasm_wasi(writable = NA), class = "nanowasm_argument_error")
  expect_error(wasm_wasi(stdout = "file"), "should be one of")
  expect_error(wasm_wasi(dirs = c(tempdir(), tempdir())), "must be named")
  expect_error(wasm_wasi(dirs = c(a = tempdir(), a = tempdir())), "unique")
  expect_error(wasm_wasi(dirs = file.path(tempdir(), "nope")), "Can't find the directory")

  wasi <- wasm_wasi()
  mod <- wasm_module(example("hello-wasi.wasm"))
  wasm_instantiate(mod, wasi = wasi)
  expect_error(wasm_instantiate(mod, wasi = wasi), "already belongs to another instance")
  expect_error(wasm_instantiate(mod, wasi = list()), class = "nanowasm_argument_error")
  expect_error(wasm_instantiate(mod, imports = 1, wasi = wasm_wasi()), class = "nanowasm_argument_error")
  expect_error(wasm_instantiate(mod), class = "nanowasm_link_error")

  expect_error(wasm_wasi_start(fixture_instance("types")), "no WASI environment")
  expect_error(wasm_wasi_start(list()), class = "nanowasm_argument_error")
  expect_error(wasm_wasi_output(wasm_wasi()), "not captured")
  expect_error(wasm_wasi_output(list()), class = "nanowasm_argument_error")
})

test_that("WASI environments print", {
  expect_snapshot(print(wasm_wasi(args = c("a", "b c"), env = c(K = "v"), stdin = "x", stdout = "capture")))
  dir <- withr_tempdir()
  out <- format(wasm_wasi(dirs = c("/data" = dir), writable = TRUE))
  expect_match(out[[6]], "/data -> .* \\(writable\\)")
  wasi <- wasm_wasi(stdout = "discard")
  wasm_wasi_start(wasm_instantiate(wasm_module(wasi_fixture("args")), wasi = wasi))
  expect_match(format(wasi), "exited with status 0", all = FALSE)
})

test_that("errors other than exit still propagate from _start", {
  mod <- wasm_module(example("hello-wasi.wasm"))
  inst <- wasm_instantiate(
    mod,
    imports = list(wasi_snapshot_preview1 = list(
      fd_write = wasm_func(function(...) stop("disk on fire"), rep("i32", 4), "i32")
    )),
    wasi = wasm_wasi()
  )
  expect_error(wasm_wasi_start(inst), "disk on fire")
})

test_that("programs set real modification times", {
  dir <- withr_tempdir()
  writeLines("x", file.path(dir, "f"))
  res <- files("touch", "f", "1600000000", dirs = dir)
  expect_identical(res$stdout, "touch ok\n")
  expect_equal(as.numeric(file.mtime(file.path(dir, "f"))), 1600000000, tolerance = 1)
  expect_identical(files("touch", "f", "1", dirs = dir, writable = FALSE)$stdout, "touch: errno 76\n")
})
