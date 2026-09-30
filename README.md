# nanowasm

<!-- badges: start -->
[![R-CMD-check](https://github.com/pedrobtz/nanowasm/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/nanowasm/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/nanowasm/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/nanowasm/actions/workflows/coverage.yaml)
<!-- badges: end -->

Run [WebAssembly](https://webassembly.org/) modules from R, with nothing to
install beyond the package itself.

nanowasm bundles the [toywasm](https://github.com/yamt/toywasm) interpreter by
YAMAMOTO Takashi, so it needs no system Wasm runtime, toolchain or download.
You load a module from a raw vector or a `.wasm` file, call its exported
functions, move data through its linear memory, and give it R functions as
imports.

> **Status: experimental.** The package is being built towards a first
> release (0.1.0); the API below is the target and may still change.

## Installation

``` r
# install.packages("pak")
pak::pak("pedrobtz/nanowasm")
```

## Usage

``` r
library(nanowasm)

path <- system.file("extdata", "fib.wasm", package = "nanowasm")
mod  <- wasm_module(path)
mod
#> <nanowasm_module> 61 bytes
#> exports:
#>   fib  function  (i32) -> i32
#> imports: none

inst <- wasm_instantiate(mod)
inst$fib(25L)
#> [1] 75025
```

Traps and other failures are classed R conditions:

``` r
tryCatch(inst$fib(1.5), nanowasm_argument_error = conditionMessage)
#> [1] "Argument 1 of `fib` (i32) must be a whole number in [-2^31, 2^32)."
```

Linear memory access, resource limits and R functions as imports are on the
way to the first release.

## Sandbox

A module can only reach the outside world through the imports you give it.
nanowasm supplies none by default: no files, network, environment variables,
clocks or randomness. Memory, call depth and running time are capped, and
traps, stack exhaustion, memory limits and timeouts are reported as classed R
conditions rather than crashes.

This makes nanowasm a safe place to run *untrusted computations*. It is not a
security boundary that has been audited against deliberately hostile code.
