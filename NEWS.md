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
* WASI: `wasm_run()` runs programs compiled for the WebAssembly System
  Interface (preview 1), and `wasm_wasi()` / `wasm_instantiate(wasi = )` /
  `wasm_wasi_start()` give finer control. Programs get the arguments and
  environment you pass, standard streams (console, captured or discarded),
  R's clocks and random numbers, and files only inside the directories you
  grant, read-only unless `writable = TRUE`.
* `wasm_stats()` reports an instance's memory use (current, peak and limit)
  and how much work it has done (runs, function calls, calls to imports,
  branches).
* `wasm_limits()` bounds an instance's memory, call depth, value stack and
  time per call; Ctrl-C interrupts a running call.
* WebAssembly exception handling (the current encoding) is enabled, so C++
  exceptions and C `setjmp`/`longjmp` work in modules built with
  `-mllvm -wasm-use-legacy-eh=false`; modules using the legacy encoding
  fail to load with a message saying how to rebuild them.
* A trap names the function it happened in, and its condition carries the
  WebAssembly call stack (`func`, `backtrace`, `depth`).
* Every failure is a classed condition (`nanowasm_trap`,
  `nanowasm_timeout`, `nanowasm_host_error`, ...); see
  `?nanowasm-conditions`.
* Modules run in the bundled toywasm interpreter (v76.0.0), so no system
  WebAssembly runtime is needed.
* `vignette("nanowasm")` walks through the API, and the example modules
  `add.wasm`, `fib.wasm`, `sum.wasm`, `log.wasm`, `hello-wasi.wasm` and
  `cat-wasi.wasm` are installed in `extdata/`.
