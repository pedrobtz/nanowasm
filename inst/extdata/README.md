# Example modules

Small WebAssembly modules used in nanowasm's examples. Each `.wasm` file is
compiled from the `.wat` or `.c` file of the same name: `.wat` with
[wabt](https://github.com/WebAssembly/wabt) 1.0.37, `.c` (WASI programs) with
[wasi-sdk](https://github.com/WebAssembly/wasi-sdk) 34
(`clang --target=wasm32-wasip1 -Oz -s`):

```sh
wat2wasm add.wat -o add.wasm
```

In the package's source repository, `tools/build-fixtures.sh` and
`tools/build-wasi-fixtures.sh` rebuild them.

| File       | Exports                                                   |
|------------|------------------------------------------------------------|
| `add.wasm` | `add(i32, i32) -> i32`, `add_f64(f64, f64) -> f64`         |
| `fib.wasm` | `fib(i32) -> i32`, the naive recursive Fibonacci function |
| `sum.wasm` | `alloc(i32) -> i32` (a bump allocator), `sum_f64(i32, i32) -> f64`, the global `heap_top`, and `memory` |
| `log.wasm` | `greet()`, which calls the import `env.log(ptr, len)` with a string in its `memory` |
| `hello-wasi.wasm` | A WASI program: greets with `$GREETING` and its arguments |
| `cat-wasi.wasm` | A WASI program: copies the files named by its arguments (or stdin) to stdout |
