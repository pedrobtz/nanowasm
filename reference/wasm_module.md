# Load a WebAssembly module

`wasm_module()` decodes and validates a WebAssembly binary. The result
can be instantiated any number of times with
[`wasm_instantiate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md).
`wasm_validate()` only checks that `x` is a valid module.

## Usage

``` r
wasm_module(x)

wasm_validate(x)
```

## Arguments

- x:

  A raw vector holding a WebAssembly binary, or the path to a `.wasm`
  file.

## Value

`wasm_module()` returns a `nanowasm_module` object. `wasm_validate()`
returns `TRUE` invisibly, or signals a `nanowasm_validation_error`.

## Details

A module cannot be saved with
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html): the restored object
is no longer valid and using it signals a `nanowasm_invalid_object`
error.

## See also

[`wasm_exports()`](https://pedrobtz.github.io/nanowasm/reference/wasm_exports.md)
to list what a module provides and needs.

## Examples

``` r
path <- system.file("extdata", "add.wasm", package = "nanowasm")
mod <- wasm_module(path)
mod
#> <nanowasm_module> 66 bytes
#> exports:
#>   add      function  (i32, i32) -> i32
#>   add_f64  function  (f64, f64) -> f64
#> imports: none

wasm_validate(path)
try(wasm_validate(as.raw(1:8)))
#> Error in wasm_validate(as.raw(1:8)) : 
#>   Invalid WebAssembly module: wrong magic: 4030201.
```
