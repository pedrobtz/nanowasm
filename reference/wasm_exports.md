# List a module's exports and imports

List a module's exports and imports

## Usage

``` r
wasm_exports(x)

wasm_imports(x)
```

## Arguments

- x:

  A `nanowasm_module` from
  [`wasm_module()`](https://pedrobtz.github.io/nanowasm/reference/wasm_module.md),
  or a `nanowasm_instance` from
  [`wasm_instantiate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md).

## Value

A data frame with one row per export (sorted by name) or import (in
module order), and columns `name`, `kind` (`"function"`, `"memory"`,
`"table"` or `"global"`) and `type`. Imports also have a `module`
column. Function types are written `"(i32, i32) -> i32"`; memories and
tables show their limits in pages or elements (`"min 1 max 2"`); globals
show their value type, prefixed with `"mut"` if mutable.

## Examples

``` r
mod <- wasm_module(system.file("extdata", "add.wasm", package = "nanowasm"))
wasm_exports(mod)
#>      name     kind              type
#> 1     add function (i32, i32) -> i32
#> 2 add_f64 function (f64, f64) -> f64
wasm_imports(mod)
#> [1] module name   kind   type  
#> <0 rows> (or 0-length row.names)
```
