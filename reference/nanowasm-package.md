# nanowasm: Run 'WebAssembly' Modules with a Bundled Interpreter

Load WebAssembly modules and call their functions from R, using the
bundled toywasm interpreter. Start with
[`vignette("nanowasm")`](https://pedrobtz.github.io/nanowasm/articles/nanowasm.md).

- [`wasm_module()`](https://pedrobtz.github.io/nanowasm/reference/wasm_module.md)
  loads a module;
  [`wasm_exports()`](https://pedrobtz.github.io/nanowasm/reference/wasm_exports.md)
  and
  [`wasm_imports()`](https://pedrobtz.github.io/nanowasm/reference/wasm_exports.md)
  describe it.

- [`wasm_instantiate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md)
  creates an instance, whose exported functions are called with
  `inst$name(...)` or
  [`wasm_call()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md).

- [`wasm_memory()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  and
  [`wasm_read()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  /
  [`wasm_write()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
  move data through linear memory, and
  [`wasm_global()`](https://pedrobtz.github.io/nanowasm/reference/wasm_global.md)
  reads and sets globals.

- [`wasm_func()`](https://pedrobtz.github.io/nanowasm/reference/wasm_func.md)
  turns an R function into an import.

- [`wasm_limits()`](https://pedrobtz.github.io/nanowasm/reference/wasm_limits.md)
  bounds memory, recursion and time, and
  [nanowasm-conditions](https://pedrobtz.github.io/nanowasm/reference/nanowasm-conditions.md)
  lists the errors nanowasm signals.

## Options

- `nanowasm.limits`: the default
  [`wasm_limits()`](https://pedrobtz.github.io/nanowasm/reference/wasm_limits.md)
  for new instances.

- `nanowasm.max_module_size`: the largest module, in bytes, that
  [`wasm_module()`](https://pedrobtz.github.io/nanowasm/reference/wasm_module.md)
  accepts (64 MB by default).

## See also

Useful links:

- <https://pedrobtz.github.io/nanowasm/>

- <https://github.com/pedrobtz/nanowasm>

- Report bugs at <https://github.com/pedrobtz/nanowasm/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- Takashi Yamamoto (Author of the bundled toywasm interpreter)
  \[copyright holder\]
