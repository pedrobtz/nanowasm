# Resource limits for an instance

`wasm_limits()` describes how much an instance may consume. Pass it to
[`wasm_instantiate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md),
or set `options(nanowasm.limits = wasm_limits(...))` to change the
default for every instance.

## Usage

``` r
wasm_limits(memory = 256 * 2^20, frames = 10000, stack = 1e+06, timeout = Inf)
```

## Arguments

- memory:

  Maximum bytes, or `Inf`.

- frames:

  Maximum call depth.

- stack:

  Maximum value-stack cells.

- timeout:

  Maximum seconds per call, or `Inf`.

## Value

A `nanowasm_limits` object.

## Details

- `memory` caps everything the interpreter allocates for the instance:
  its linear memories, tables, globals and the stacks of running calls.
  A `memory.grow` that would exceed it fails inside WebAssembly
  (returning -1, as the specification requires). Any other allocation
  that would exceed it signals a `nanowasm_memory_limit` error.

- `frames` is the maximum call depth, and `stack` the maximum number of
  value-stack cells (4 bytes each). Exceeding either signals a
  `nanowasm_stack_exhausted` error.

- `timeout` is the wall-clock time a single call (including the start
  function at instantiation) may run, in seconds. Exceeding it signals a
  `nanowasm_timeout` error. It is checked about every 50 milliseconds of
  execution.

Pressing Ctrl-C (or Esc) interrupts a running call regardless of the
limits, as it does for R code.

A call stopped by a limit or an interrupt may leave the instance's
memory and globals partly updated. The instance stays usable, but
whether its state still makes sense depends on the module.

## Examples

``` r
wasm_limits()
#> <nanowasm_limits>
#>   memory:  256 MiB
#>   frames:  10,000
#>   stack:   1,000,000 cells
#>   timeout: none
wasm_limits(memory = 16 * 2^20, timeout = 1)
#> <nanowasm_limits>
#>   memory:  16 MiB
#>   frames:  10,000
#>   stack:   1,000,000 cells
#>   timeout: 1 s

mod <- wasm_module(system.file("extdata", "fib.wasm", package = "nanowasm"))
inst <- wasm_instantiate(mod, limits = wasm_limits(timeout = 0.5))
try(inst$fib(40L))
#> Error in inst$fib(40L) : 
#>   The WebAssembly call was stopped after 0.5 seconds, its time limit.
```
