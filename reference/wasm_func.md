# Give a module an R function as an import

`wasm_func()` wraps an R function so a module can import it. Pass it to
[`wasm_instantiate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md)
in `imports`, a list of lists named by the module's import module and
field names:

## Usage

``` r
wasm_func(fn, params = character(), results = character())
```

## Arguments

- fn:

  An R function.

- params, results:

  Character vectors of WebAssembly value types: `"i32"`, `"i64"`,
  `"f32"` or `"f64"`.

## Value

A `nanowasm_func`.

## Details

    imports = list(env = list(log_i32 = wasm_func(function(x) message(x), "i32")))

When the WebAssembly code calls the import, the R function receives the
arguments converted as described in
[`wasm_instantiate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md),
and its return value is converted back and checked against `results`:
nothing is expected when `results` is empty, a single value when it has
one type, and a list of values when it has several.

If the R function has a parameter named `caller`, it also receives a
`nanowasm_caller`, whose `memory()` returns the calling instance's
memory (see
[`wasm_memory()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)).
This is how an import reads a string or buffer the module passes by
pointer. The caller is only valid during the call.

An error in the R function stops the WebAssembly call, which signals a
`nanowasm_host_error`. Its `parent` field holds the original condition.
An interrupt or other jump out of the R function unwinds the WebAssembly
call too, and the instance remains usable. An instance runs one call at
a time, so an import cannot call back into its own instance: that
signals a `nanowasm_reentry_error`.

## Examples

``` r
mod <- wasm_module(system.file("extdata", "log.wasm", package = "nanowasm"))
wasm_imports(mod)
#>   module name     kind             type
#> 1    env  log function (i32, i32) -> ()

log_str <- function(ptr, len, caller) {
  msg <- wasm_read_string(caller$memory(), ptr, len)
  message("module says: ", msg)
}
inst <- wasm_instantiate(mod, imports = list(
  env = list(log = wasm_func(log_str, params = c("i32", "i32")))
))
inst$greet()
#> module says: Hello from WebAssembly!
```
