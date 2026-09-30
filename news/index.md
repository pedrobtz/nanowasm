# Changelog

## nanowasm 0.0.0.9003

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
  creates an instance (running the start function), and
  [`wasm_call()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md)
  or `inst$name(...)` calls its exported functions, converting `i32`,
  `i64`, `f32` and `f64` values to and from R.
- Traps, invalid modules and bad arguments signal classed conditions
  (`nanowasm_trap`, `nanowasm_validation_error`,
  `nanowasm_argument_error`, …); see `?nanowasm-conditions`.
- Example modules `add.wasm` and `fib.wasm` are installed in `extdata/`.

## nanowasm 0.0.0.9002

- Bundles the toywasm WebAssembly interpreter (v76.0.0). It is built
  with the package but not yet exposed through an R API.

## nanowasm 0.0.0.9001

- Package skeleton. No user-facing functionality yet.
