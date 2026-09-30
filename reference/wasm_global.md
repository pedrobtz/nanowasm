# Read and write an instance's exported globals

`wasm_global()` returns the current value of an exported global,
converted as described in
[`wasm_instantiate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md).
`wasm_global<-` sets a mutable one; setting an immutable global is an
error.

## Usage

``` r
wasm_global(instance, name)

wasm_global(instance, name) <- value
```

## Arguments

- instance:

  A `nanowasm_instance`.

- name:

  The export name of the global.

- value:

  The new value.

## Value

`wasm_global()` returns the value. `wasm_global<-` returns the instance,
whose global has been changed in place.

## Examples

``` r
mod <- wasm_module(system.file("extdata", "sum.wasm", package = "nanowasm"))
inst <- wasm_instantiate(mod)
wasm_global(inst, "heap_top")
#> [1] 1024
inst$alloc(64L)
#> [1] 1024
wasm_global(inst, "heap_top")
#> [1] 1088
wasm_global(inst, "heap_top") <- 4096L
inst$alloc(8L)
#> [1] 4096
```
