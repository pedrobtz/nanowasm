# Package index

## Modules

Load and inspect WebAssembly modules.

- [`wasm_module()`](https://pedrobtz.github.io/nanowasm/reference/wasm_module.md)
  [`wasm_validate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_module.md)
  : Load a WebAssembly module
- [`wasm_exports()`](https://pedrobtz.github.io/nanowasm/reference/wasm_exports.md)
  [`wasm_imports()`](https://pedrobtz.github.io/nanowasm/reference/wasm_exports.md)
  : List a module's exports and imports

## Instances and calls

Instantiate a module and call its functions.

- [`wasm_instantiate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md)
  [`wasm_call()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md)
  : Instantiate a module and call its functions
- [`wasm_global()`](https://pedrobtz.github.io/nanowasm/reference/wasm_global.md)
  [`` `wasm_global<-`() ``](https://pedrobtz.github.io/nanowasm/reference/wasm_global.md)
  : Read and write an instance's exported globals
- [`wasm_limits()`](https://pedrobtz.github.io/nanowasm/reference/wasm_limits.md)
  : Resource limits for an instance

## Linear memory

Move data between R and an instance’s memory.

- [`wasm_memory()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  [`wasm_read()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  [`wasm_write()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  [`wasm_read_string()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  [`wasm_write_string()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  [`wasm_memory_size()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  [`wasm_memory_grow()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  : Access an instance's linear memory

## Imports

Let a module call R.

- [`wasm_func()`](https://pedrobtz.github.io/nanowasm/reference/wasm_func.md)
  : Give a module an R function as an import

## Errors

- [`nanowasm-conditions`](https://pedrobtz.github.io/nanowasm/reference/nanowasm-conditions.md)
  : Conditions signalled by nanowasm

## Package

- [`nanowasm`](https://pedrobtz.github.io/nanowasm/reference/nanowasm-package.md)
  [`nanowasm-package`](https://pedrobtz.github.io/nanowasm/reference/nanowasm-package.md)
  : nanowasm: Run 'WebAssembly' Modules with a Bundled Interpreter
