# Resource usage of an instance

`wasm_stats()` reports what an instance has consumed so far:

## Usage

``` r
wasm_stats(instance)
```

## Arguments

- instance:

  A `nanowasm_instance`.

## Value

A `nanowasm_stats` object: a list of numbers (bytes and counts), with a
print method.

## Details

- `memory`: bytes the interpreter currently holds for the instance (its
  linear memories, tables, globals and other internal state), the
  quantity that
  [`wasm_limits()`](https://pedrobtz.github.io/nanowasm/reference/wasm_limits.md)'
  `memory` limit applies to; `memory_peak`, the most it has held at
  once; and `memory_limit`.

- `runs`: how many times WebAssembly code has run in the instance: calls
  from R (including through `$`), plus the start function.

- `calls`: WebAssembly functions called during those runs, counting
  `host_calls`, the calls to imported functions (R functions and WASI).

- `branches`: branch instructions taken, a rough measure of how much
  work the code did.

Counts are cumulative over the instance's life. Linear memory is
allocated as the module touches it, so `memory` can be well below the
memory's declared size.

## Examples

``` r
mod <- wasm_module(system.file("extdata", "fib.wasm", package = "nanowasm"))
inst <- wasm_instantiate(mod)
inst$fib(20L)
#> [1] 6765
wasm_stats(inst)
#> <nanowasm_stats>
#>   memory:     136 bytes (peak 1.04 KiB, limit 256 MiB)
#>   runs:       2
#>   calls:      21,891 (0 to imports)
#>   branches:   32,837

# fib(n) makes 2 * fib(n + 1) - 1 calls.
before <- wasm_stats(inst)$calls
inst$fib(10L)
#> [1] 55
wasm_stats(inst)$calls - before
#> [1] 177
```
