fixture <- function(name) {
  test_path("fixtures", paste0(name, ".wasm"))
}

fixture_instance <- function(name) {
  wasm_instantiate(wasm_module(fixture(name)))
}

# Tests that deliver a real SIGINT to the R process. Valgrind mishandles the
# signal and R's siglongjmp out of a blocking select(): it reports invalid
# stack accesses inside select() and the run aborts, while the same tests
# are clean under ASan and UBSan. Skip them there.
skip_if_signals_unreliable <- function() {
  skip_on_cran()
  skip_on_os("windows")
  maps <- if (file.exists("/proc/self/maps")) readLines("/proc/self/maps", warn = FALSE) else character()
  skip_if(any(grepl("vgpreload", maps, fixed = TRUE)), "running under valgrind")
}

# A temporary directory removed when the calling test ends.
withr_tempdir <- function(env = parent.frame()) {
  dir <- tempfile()
  dir.create(dir)
  dir <- normalizePath(dir, winslash = "/")
  do.call(on.exit, list(substitute(unlink(dir, recursive = TRUE), list(dir = dir)), add = TRUE), envir = env)
  dir
}

# writeLines() with "\n" endings on every platform (it writes "\r\n" on
# Windows), for files a WASI program reads byte for byte.
write_lines_lf <- function(text, path) {
  writeBin(charToRaw(paste0(text, "\n", collapse = "")), path)
}
