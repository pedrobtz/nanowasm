# Conditions signalled by nanowasm

Every error nanowasm raises has class `nanowasm_error`, plus a more
specific class that code can catch with
[`tryCatch()`](https://rdrr.io/r/base/conditions.html):

## Details

- `nanowasm_invalid_object`: the object no longer points at a live
  module or instance, for example after a
  [`saveRDS()`](https://rdrr.io/r/base/readRDS.html) /
  [`readRDS()`](https://rdrr.io/r/base/readRDS.html) round trip.

- `nanowasm_validation_error`: the bytes are not a valid WebAssembly
  module.

- `nanowasm_link_error`: the module cannot be instantiated with the
  imports given. The `missing` field lists missing imports.

- `nanowasm_argument_error`: a value passed from R does not fit the
  function's signature. Its subclass `nanowasm_precision_error` is used
  when an `i64` result cannot be represented exactly as a double.

- `nanowasm_unsupported`: the function uses a type nanowasm cannot pass
  between R and WebAssembly (`funcref`, `externref`, `v128`).

- `nanowasm_trap`: the WebAssembly code trapped. `trap_id` names the
  trap (`"div_by_zero"`, `"unreachable"`,
  `"out_of_bounds_memory_access"`, ...) and `detail` holds the
  interpreter's own message. Subclasses: `nanowasm_stack_exhausted`
  (call or value stack limit) and `nanowasm_out_of_bounds` (memory or
  table access out of bounds).

- `nanowasm_memory_limit`: the instance reached its memory limit (see
  [`wasm_limits()`](https://pedrobtz.github.io/nanowasm/reference/wasm_limits.md)),
  or the interpreter could not allocate memory.

- `nanowasm_timeout`: a call ran longer than its time limit. `elapsed`
  and `limit` are in seconds.

- `nanowasm_reentry_error`: an instance was called while already running
  a call.

- `nanowasm_runtime_error`: any other failure inside the interpreter.

Out-of-bounds
[`wasm_read()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
and
[`wasm_write()`](https://pedrobtz.github.io/nanowasm/reference/wasm_memory.md)
calls signal `nanowasm_out_of_bounds` too, as a subclass of
`nanowasm_argument_error`.

Pressing Ctrl-C during a call signals R's usual `interrupt` condition.

## Examples

``` r
mod <- wasm_module(system.file("extdata", "add.wasm", package = "nanowasm"))
inst <- wasm_instantiate(mod)
tryCatch(
  inst$add(1L),
  nanowasm_argument_error = function(e) conditionMessage(e)
)
#> [1] "`add` takes 2 arguments but was given 1."
```
