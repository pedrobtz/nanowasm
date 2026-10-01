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

Once nanowasm is on CRAN:

``` r
install.packages("nanowasm")
```

The development version from GitHub:

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

Data moves through the module's linear memory. WebAssembly has no standard
allocator, so ask the module for space:

``` r
inst <- wasm_instantiate(wasm_module(system.file("extdata", "sum.wasm", package = "nanowasm")))
mem  <- wasm_memory(inst)

x   <- c(1.5, 2.5, 3, 4, 5)
ptr <- inst$alloc(8L * length(x))
wasm_write(mem, ptr, x, "f64")
inst$sum_f64(ptr, length(x))
#> [1] 16
```

Every instance runs under resource limits:

``` r
inst <- wasm_instantiate(mod, limits = wasm_limits(memory = 16 * 2^20, timeout = 1))
inst$fib(45L)
#> Error in inst$fib(45L) :
#>   The WebAssembly call was stopped after 1 second, its time limit.
```

Modules can call back into R through imports:

``` r
mod <- wasm_module(system.file("extdata", "log.wasm", package = "nanowasm"))
log <- wasm_func(function(ptr, len, caller) {
  message(wasm_read_string(caller$memory(), ptr, len))
}, params = c("i32", "i32"))

inst <- wasm_instantiate(mod, imports = list(env = list(log = log)))
inst$greet()
#> Hello from WebAssembly!
```

Programs compiled for WASI (C with wasi-sdk, Rust's `wasm32-wasip1`, ...)
run with `wasm_run()`, which gives them arguments, environment variables,
standard streams, clocks, random numbers and only the directories you grant:

``` r
hello <- system.file("extdata", "hello-wasi.wasm", package = "nanowasm")
wasm_run(hello, args = c("from", "R"), env = c(GREETING = "Hi"))
#> <nanowasm_run> exit status 0
#> -- stdout --
#> Hi from R!
```

## Sandbox

A module can only reach the outside world through the imports you give it.
nanowasm supplies none by default: no files, network, environment variables,
clocks or randomness. For WASI programs it provides only what you pass:
arguments, environment variables, the directories you grant (read-only by
default), and R's clocks and random numbers; never sockets. Memory, call depth and running time are capped, and
traps, stack exhaustion, memory limits and timeouts are reported as classed R
conditions rather than crashes.

This makes nanowasm a safe place to run *untrusted computations*. It is not a
security boundary that has been audited against deliberately hostile code.
