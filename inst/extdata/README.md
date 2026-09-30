# Example modules

Small WebAssembly modules used in nanowasm's examples. Each `.wasm` file is
compiled from the `.wat` file of the same name with
[wabt](https://github.com/WebAssembly/wabt) 1.0.37:

```sh
wat2wasm add.wat -o add.wasm
```

In the package's source repository, `tools/build-fixtures.sh` rebuilds all of
them.

| File       | Exports                                                   |
|------------|-----------------------------------------------------------|
| `add.wasm` | `add(i32, i32) -> i32`, `add_f64(f64, f64) -> f64`         |
| `fib.wasm` | `fib(i32) -> i32`, the naive recursive Fibonacci function |
