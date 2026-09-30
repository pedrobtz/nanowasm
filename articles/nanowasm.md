# Getting started with nanowasm

nanowasm runs [WebAssembly](https://webassembly.org/) modules from R.
The interpreter, [toywasm](https://github.com/yamt/toywasm), is bundled
with the package, so there is nothing else to install.

This vignette walks through the whole API with the small example modules
installed with the package: loading a module, calling its functions,
moving data through its memory, giving it R functions to call, and
limiting what it can consume.

``` r

library(nanowasm)
example <- function(name) system.file("extdata", name, package = "nanowasm")
```

## Modules and instances

A *module* is compiled WebAssembly code: a `.wasm` file, or the same
bytes in a raw vector.
[`wasm_module()`](https://pedrobtz.github.io/nanowasm/reference/wasm_module.md)
decodes and validates it, and printing it shows what it exports and
imports:

``` r

mod <- wasm_module(example("fib.wasm"))
mod
#> <nanowasm_module> 61 bytes
#> exports:
#>   fib  function  (i32) -> i32
#> imports: none
```

An *instance* is a module brought to life, with its own memory, tables
and globals. Calls go to an instance:

``` r

inst <- wasm_instantiate(mod)
inst$fib(20L)
#> [1] 6765
wasm_call(inst, "fib", 20L)
#> [1] 6765
```

A module can be instantiated as many times as you like, and instances
don’t share state.

## Values

WebAssembly functions take and return four number types. They map to R
like this:

| WebAssembly  | from R                                     | to R    |
|--------------|--------------------------------------------|---------|
| `i32`        | integer, or a whole double in \[-2³¹, 2³²) | integer |
| `i64`        | a whole number with magnitude at most 2⁵³  | double  |
| `f32`, `f64` | integer or double                          | double  |

Arguments are checked against the signature, and a mismatch is an error
rather than a silent coercion:

``` r

add <- wasm_instantiate(wasm_module(example("add.wasm")))
add$add(2L, 3L)
#> [1] 5
add$add_f64(0.5, 0.25)
#> [1] 0.75
add$add(2.5, 1L)
#> Error in `add$add()`:
#> ! Argument 1 of `add` (i32) must be a whole number in [-2^31, 2^32).
```

A function with several results returns them as a list, and one with
none returns `NULL` invisibly.

## Linear memory

Calls pass numbers only. Anything larger, such as a vector or a string,
travels through the instance’s *linear memory*, a byte array that the
module reads and writes with pointers (byte offsets).
[`wasm_memory()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
gives R the same view:

``` r

inst <- wasm_instantiate(wasm_module(example("sum.wasm")))
mem <- wasm_memory(inst)
mem
#> <nanowasm_memory> `memory`: 1 page (64 KiB)
```

WebAssembly has no standard allocator, so R has to ask the module where
it may write. `sum.wasm` exports a simple `alloc()`:

``` r

x <- c(1.5, 2.5, 3, 4, 5)
ptr <- inst$alloc(8L * length(x))
wasm_write(mem, ptr, x, type = "f64")
inst$sum_f64(ptr, length(x))
#> [1] 16
wasm_read(mem, ptr, length(x), type = "f64")
#> [1] 1.5 2.5 3.0 4.0 5.0
```

`type` can be `"raw"`, `"i8"`, `"u8"`, `"i16"`, `"u16"`, `"i32"`,
`"u32"`, `"i64"`, `"u64"`, `"f32"` or `"f64"`. Offsets are 0-based byte
addresses, the numbers the module itself uses, not 1-based R indices.
Every access is bounds-checked:

``` r

wasm_read(mem, wasm_memory_size(mem) - 2, 4)
#> Error in `wasm_read()`:
#> ! Access of 4 bytes at offset 65534 is out of bounds of the memory (65536 bytes).
```

Strings are UTF-8:

``` r

end <- wasm_write_string(mem, 2048, "héllo")
wasm_read_string(mem, 2048)
#> [1] "héllo"
```

Exported globals are read with
[`wasm_global()`](https://pedrobtz.github.io/nanowasm/reference/wasm_global.md)
and set with `wasm_global<-`:

``` r

wasm_global(inst, "heap_top")
#> [1] 1064
```

## Calling R from WebAssembly

A module can declare *imports*: functions it expects its host to
provide.
[`wasm_imports()`](https://pedrobtz.github.io/nanowasm/reference/wasm_exports.md)
lists them:

``` r

logmod <- wasm_module(example("log.wasm"))
wasm_imports(logmod)
#>   module name     kind             type
#> 1    env  log function (i32, i32) -> ()
```

Provide them as R functions wrapped with
[`wasm_func()`](https://pedrobtz.github.io/nanowasm/reference/wasm_func.md),
which records the signature, in a list of lists named by import module
and field. A function with a `caller` argument can reach the calling
instance’s memory, which is how this one reads the string the module
passes by pointer and length:

``` r

log <- wasm_func(
  function(ptr, len, caller) {
    message("module says: ", wasm_read_string(caller$memory(), ptr, len))
  },
  params = c("i32", "i32")
)
inst <- wasm_instantiate(logmod, imports = list(env = list(log = log)))
inst$greet()
#> module says: Hello from WebAssembly!
```

Linking checks every import before anything runs, and reports all
missing or mismatched imports together:

``` r

wasm_instantiate(logmod, imports = list(env = list(log = wasm_func(identity, "i32"))))
#> Error in `wasm_instantiate()`:
#> ! Can't link the module's imports:
#> - `env.log` has type (i32, i32) -> () but the R function was declared as (i32) -> ().
```

If the R function fails, the WebAssembly call stops with a
`nanowasm_host_error` that carries the original condition as `parent`.
Interrupts, restarts and other jumps out of the R function also unwind
the WebAssembly call safely, and the instance stays usable.

## Limits and errors

Every instance runs under limits set by
[`wasm_limits()`](https://pedrobtz.github.io/nanowasm/reference/wasm_limits.md):
memory, call depth, value-stack size and time per call.

``` r

slow <- wasm_instantiate(
  wasm_module(example("fib.wasm")),
  limits = wasm_limits(memory = 16 * 2^20, timeout = 0.5)
)
slow$fib(40L)
#> Error in `slow$fib()`:
#> ! The WebAssembly call was stopped after 0.5 seconds, its time limit.
```

Set `options(nanowasm.limits = wasm_limits(...))` to change the default
for every instance. Ctrl-C interrupts a running call, just as it does R
code.

Every error nanowasm signals has class `nanowasm_error` and a more
specific class, so programs can react to each kind of failure:

``` r

res <- tryCatch(
  slow$fib(40L),
  nanowasm_timeout = function(e) "too slow",
  nanowasm_trap = function(e) paste("trapped:", e$trap_id)
)
res
#> [1] "too slow"
```

See
[`?"nanowasm-conditions"`](https://pedrobtz.github.io/nanowasm/reference/nanowasm-conditions.md)
for the full list: traps (with a `trap_id` such as `"div_by_zero"` or
`"unreachable"`), stack exhaustion, memory limits, timeouts, link and
validation errors, and errors in imported R functions.

## What the sandbox guarantees

A module can only affect the outside world through the imports you give
it, and nanowasm gives it none by default. It has no files, network,
environment variables, clock or random numbers unless an R function you
import provides them. What it can consume is bounded:

- **Memory**: everything the interpreter allocates for an instance
  (memories, tables and call stacks) counts against
  `wasm_limits(memory = )`.
- **Time**: each call is stopped after `wasm_limits(timeout = )`, and
  Ctrl-C always works.
- **Recursion**: deep calls end in a `nanowasm_stack_exhausted` error
  rather than a crash.

This makes nanowasm a sound way to run *untrusted computations*: a
module that loops, recurses or allocates without end is stopped with an
error, and R carries on. It is **not** a security boundary that has been
audited against deliberately hostile code. The interpreter and the glue
around it are tested, fuzzed and checked with sanitizers, but not
formally verified. Treat a module you don’t trust as you would treat an
R package you don’t trust, and don’t give it imports that can do more
than it needs.

## Getting modules

Any toolchain that targets WebAssembly can produce modules for nanowasm,
as long as the module doesn’t need WASI or other system imports:

- **The text format**, compiled with
  [wabt](https://github.com/WebAssembly/wabt)’s `wat2wasm`. This is how
  the example modules were made; their sources are installed next to
  them.
- **C**, with clang:
  `clang --target=wasm32 -nostdlib -O2 -Wl,--no-entry -Wl,--export-all -o lib.wasm lib.c`.
- **Rust**, with the `wasm32-unknown-unknown` target and a `cdylib`
  crate.
