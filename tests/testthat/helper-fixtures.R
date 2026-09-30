fixture <- function(name) {
  test_path("fixtures", paste0(name, ".wasm"))
}

fixture_instance <- function(name) {
  wasm_instantiate(wasm_module(fixture(name)))
}
