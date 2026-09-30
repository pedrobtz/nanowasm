# Version of the vendored toywasm interpreter, e.g. "v76.0.0".
toywasm_version <- function() {
  .Call(nw_toywasm_version)
}
