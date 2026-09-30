# Instantiate a module and call its functions

`wasm_instantiate()` creates an instance of a module: it allocates the
module's memories, tables and globals, initialises them, and runs the
module's start function if it has one. `wasm_call()` calls one of the
instance's exported functions. `inst$name(...)` is shorthand for
`wasm_call(inst, "name", ...)`.

## Usage

``` r
wasm_instantiate(module)

wasm_call(instance, name, ...)
```

## Arguments

- module:

  A `nanowasm_module` from
  [`wasm_module()`](https://pedrobtz.github.io/nanowasm/reference/wasm_module.md).

- instance:

  A `nanowasm_instance` from `wasm_instantiate()`.

- name:

  The name of an exported function.

- ...:

  The function's arguments, in order.

## Value

`wasm_instantiate()` returns a `nanowasm_instance`. `wasm_call()`
returns the function's results as described above.

## Details

Calls are scalar: each argument is one value, matched to the function's
parameter types.

- `i32` accepts an integer, or a double holding a whole number in
  \\\[-2^{31}, 2^{32})\\; values from \\2^{31}\\ up are taken as the
  unsigned bit pattern. `i32` results are integers. `NA_integer_` shares
  its bits with \\-2^{31}\\, so the two are the same value in
  WebAssembly.

- `i64` accepts a whole number with magnitude at most \\2^{53}\\, and
  `i64` results are doubles. A result that a double cannot represent
  exactly signals a `nanowasm_precision_error` rather than being
  rounded.

- `f32` and `f64` accept numbers, and return doubles.

A function with no results returns `NULL` invisibly, one with a single
result returns it as a length-one vector, and one with several results
returns an unnamed list.

If the WebAssembly code traps, the call signals a `nanowasm_trap` (see
[nanowasm-conditions](https://pedrobtz.github.io/nanowasm/reference/nanowasm-conditions.md)).
Calls are limited to 10,000 nested frames and 1,000,000 value-stack
cells, so runaway recursion signals a `nanowasm_stack_exhausted` error
rather than exhausting memory.

## Examples

``` r
mod <- wasm_module(system.file("extdata", "fib.wasm", package = "nanowasm"))
inst <- wasm_instantiate(mod)
inst$fib(20L)
#> [1] 6765
wasm_call(inst, "fib", 10L)
#> [1] 55
```
