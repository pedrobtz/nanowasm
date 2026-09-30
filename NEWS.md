# nanowasm 0.0.0.9005

* Modules can import R functions: wrap them with `wasm_func()` and pass them
  to `wasm_instantiate(imports = )`. Linking reports every missing or
  mismatched import at once. An R function with a `caller` argument can
  reach the calling instance's memory through `caller$memory()`.
* An error in an imported R function signals a `nanowasm_host_error` whose
  `parent` is the original condition; interrupts, restarts and other jumps
  out of an import unwind the WebAssembly call safely.
* New example module `log.wasm`.

# nanowasm 0.0.0.9004

* `wasm_memory()` gives access to an instance's linear memory:
  `wasm_read()` / `wasm_write()` for typed vectors, `wasm_read_string()` /
  `wasm_write_string()` for UTF-8 strings, and `wasm_memory_size()` /
  `wasm_memory_grow()`. Offsets are 0-based byte addresses and every access
  is bounds-checked.
* `wasm_global()` reads an exported global, and `wasm_global<-` sets a
  mutable one.
* `wasm_limits()` sets an instance's memory, call-depth, value-stack and
  time limits, passed to `wasm_instantiate(limits = )` or set for all
  instances with `options(nanowasm.limits = )`. A call that runs too long
  signals `nanowasm_timeout`, and Ctrl-C interrupts a running call.
* New example module `sum.wasm`, with a bump allocator.

# nanowasm 0.0.0.9003

* `wasm_module()` loads and validates a WebAssembly module from a raw vector
  or a `.wasm` file; `wasm_validate()` only checks it. `wasm_exports()` and
  `wasm_imports()` list what a module provides and needs.
* `wasm_instantiate()` creates an instance (running the start function), and
  `wasm_call()` or `inst$name(...)` calls its exported functions, converting
  `i32`, `i64`, `f32` and `f64` values to and from R.
* Traps, invalid modules and bad arguments signal classed conditions
  (`nanowasm_trap`, `nanowasm_validation_error`, `nanowasm_argument_error`,
  ...); see `?nanowasm-conditions`.
* Example modules `add.wasm` and `fib.wasm` are installed in `extdata/`.

# nanowasm 0.0.0.9002

* Bundles the toywasm WebAssembly interpreter (v76.0.0). It is built with the
  package but not yet exposed through an R API.

# nanowasm 0.0.0.9001

* Package skeleton. No user-facing functionality yet.
