# nanowasm 0.0.0.9000

Development version, heading for the first release (0.1.0).

* `wasm_module()` loads and validates a WebAssembly module from a raw vector
  or a `.wasm` file; `wasm_validate()` only checks it. `wasm_exports()` and
  `wasm_imports()` list what a module provides and needs.
* `wasm_instantiate()` creates an instance (running its start function), and
  `wasm_call()` or `inst$name(...)` calls its exported functions, converting
  `i32`, `i64`, `f32` and `f64` values to and from R.
* `wasm_memory()` gives access to an instance's linear memory:
  `wasm_read()` / `wasm_write()` for typed vectors, `wasm_read_string()` /
  `wasm_write_string()` for UTF-8 strings, and `wasm_memory_size()` /
  `wasm_memory_grow()`. `wasm_global()` reads and sets exported globals.
* Modules can import R functions: wrap them with `wasm_func()` and pass them
  to `wasm_instantiate(imports = )`. An R function with a `caller` argument
  can reach the calling instance's memory.
* `wasm_limits()` bounds an instance's memory, call depth, value stack and
  time per call; Ctrl-C interrupts a running call.
* Every failure is a classed condition (`nanowasm_trap`,
  `nanowasm_timeout`, `nanowasm_host_error`, ...); see
  `?nanowasm-conditions`.
* Modules run in the bundled toywasm interpreter (v76.0.0), so no system
  WebAssembly runtime is needed.
* `vignette("nanowasm")` walks through the API, and the example modules
  `add.wasm`, `fib.wasm`, `sum.wasm` and `log.wasm` are installed in
  `extdata/`.
