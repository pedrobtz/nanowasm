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
