# Changelog

## nanowasm 0.0.0.9000

Development version, heading for the first release (0.1.0).

- [`wasm_module()`](https://pedrobtz.github.io/nanowasm/reference/wasm_module.md)
  loads and validates a WebAssembly module from a raw vector or a
  `.wasm` file;
  [`wasm_validate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_module.md)
  only checks it.
  [`wasm_exports()`](https://pedrobtz.github.io/nanowasm/reference/wasm_exports.md)
  and
  [`wasm_imports()`](https://pedrobtz.github.io/nanowasm/reference/wasm_exports.md)
  list what a module provides and needs.
- [`wasm_instantiate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md)
  creates an instance (running its start function), and
  [`wasm_call()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md)
  or `inst$name(...)` calls its exported functions, converting `i32`,
  `i64`, `f32` and `f64` values to and from R.
- [`wasm_memory()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  gives access to an instance’s linear memory:
  [`wasm_read()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  /
  [`wasm_write()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  for typed vectors,
  [`wasm_read_string()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  /
  [`wasm_write_string()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  for UTF-8 strings, and
  [`wasm_memory_size()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  /
  [`wasm_memory_grow()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md).
  [`wasm_global()`](https://pedrobtz.github.io/nanowasm/reference/wasm_global.md)
  reads and sets exported globals.
- Modules can import R functions: wrap them with
  [`wasm_func()`](https://pedrobtz.github.io/nanowasm/reference/wasm_func.md)
  and pass them to `wasm_instantiate(imports = )`. An R function with a
  `caller` argument can reach the calling instance’s memory.
- [`wasm_limits()`](https://pedrobtz.github.io/nanowasm/reference/wasm_limits.md)
  bounds an instance’s memory, call depth, value stack and time per
  call; Ctrl-C interrupts a running call.
- Every failure is a classed condition (`nanowasm_trap`,
  `nanowasm_timeout`, `nanowasm_host_error`, …); see
  `?nanowasm-conditions`.
- Modules run in the bundled toywasm interpreter (v76.0.0), so no system
  WebAssembly runtime is needed.
- [`vignette("nanowasm")`](https://pedrobtz.github.io/nanowasm/articles/nanowasm.md)
  walks through the API, and the example modules `add.wasm`, `fib.wasm`,
  `sum.wasm` and `log.wasm` are installed in `extdata/`.
