# nanowasm: Run 'WebAssembly' Modules with a Bundled Interpreter

Loads 'WebAssembly' modules from raw vectors or files and calls their
exported functions from R. Modules run in a bundled interpreter, so no
system 'WebAssembly' runtime is needed. R vectors can be copied into and
out of a module's linear memory, and R functions can be supplied as
imports. Modules are sandboxed: they have no access to files, network or
environment beyond the imports they are given, and traps, stack
exhaustion, memory growth and timeouts are reported as classed R
conditions.

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
