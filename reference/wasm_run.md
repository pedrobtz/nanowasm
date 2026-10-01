# Run a WASI program

`wasm_run()` runs a WASI command module (one that exports `_start`, as
programs built with wasi-sdk or Rust's `wasm32-wasip1` target do) from
start to finish, and returns its exit status and captured output. It is
[`wasm_wasi()`](https://pedrobtz.github.io/nanowasm/reference/wasm_wasi.md),
[`wasm_instantiate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md)
and
[`wasm_wasi_start()`](https://pedrobtz.github.io/nanowasm/reference/wasm_wasi.md)
in one call; see
[`wasm_wasi()`](https://pedrobtz.github.io/nanowasm/reference/wasm_wasi.md)
for what the program can and can't reach.

## Usage

``` r
wasm_run(
  module,
  args = character(),
  env = character(),
  stdin = NULL,
  dirs = character(),
  writable = FALSE,
  stdout = c("capture", "console", "discard"),
  stderr = c("capture", "console", "discard"),
  imports = list(),
  limits = NULL,
  program = "main"
)
```

## Arguments

- module:

  A `nanowasm_module`, or anything
  [`wasm_module()`](https://pedrobtz.github.io/nanowasm/reference/wasm_module.md)
  accepts.

- args:

  Command-line arguments, after the program name.

- env:

  Environment variables, as a named character vector.

- stdin:

  Standard input: `NULL` for none, a character vector (written as lines)
  or a raw vector.

- dirs:

  Directories the program may use, as a character vector of host paths
  named by the path the program sees them at (`c("/data" = "~/x")`). A
  single unnamed directory is seen as the program's current directory,
  so relative paths resolve inside it.

- writable:

  Whether the program may create, change and delete files in `dirs`.

- stdout, stderr:

  Where the program's output goes: `"capture"` (the default; returned in
  the result), `"console"` or `"discard"`.

- imports:

  Other imports the module needs, as for
  [`wasm_instantiate()`](https://pedrobtz.github.io/nanowasm/reference/wasm_instantiate.md).

- limits:

  Resource limits from
  [`wasm_limits()`](https://pedrobtz.github.io/nanowasm/reference/wasm_limits.md).

- program:

  The program name the module sees as its first argument.

## Value

A `nanowasm_run` object: a list with the exit `status` and, for captured
streams, the `stdout` and `stderr` text.

## Examples

``` r
hello <- system.file("extdata", "hello-wasi.wasm", package = "nanowasm")
res <- wasm_run(hello, args = c("from", "R"), env = c(GREETING = "Hi"))
res
#> <nanowasm_run> exit status 0
#> -- stdout --
#> Hi from R!
res$stdout
#> [1] "Hi from R!\n"

# The program can only see the directories you grant.
dir <- tempfile()
dir.create(dir)
writeLines(c("a,b", "1,2"), file.path(dir, "data.csv"))
cat_wasm <- system.file("extdata", "cat-wasi.wasm", package = "nanowasm")
wasm_run(cat_wasm, args = "data.csv", dirs = dir)$stdout
#> [1] "a,b\n1,2\n"
wasm_run(cat_wasm, args = "../secret.txt", dirs = dir)
#> <nanowasm_run> exit status 1
#> -- stderr --
#> cat: ../secret.txt: Capabilities insufficient
```
