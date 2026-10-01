# Run WASI programs

WASI (the WebAssembly System Interface, "preview 1") is how WebAssembly
programs compiled from C, C++, Rust and other languages reach the
outside world: command-line arguments, environment variables, standard
input and output, clocks, random numbers and files. `wasm_wasi()`
describes what a program may see; `wasm_instantiate(wasi = )` provides
it to an instance; `wasm_wasi_start()` runs the program; and
[`wasm_run()`](https://pedrobtz.github.io/nanowasm/reference/wasm_run.md)
does all three in one call.

## Usage

``` r
wasm_wasi(
  args = character(),
  env = character(),
  stdin = NULL,
  stdout = c("console", "capture", "discard"),
  stderr = c("console", "capture", "discard"),
  dirs = character(),
  writable = FALSE,
  program = "main"
)

wasm_wasi_start(instance)

wasm_wasi_output(wasi, stream = c("stdout", "stderr"))
```

## Arguments

- args:

  Command-line arguments, after the program name.

- env:

  Environment variables, as a named character vector.

- stdin:

  Standard input: `NULL` for none, a character vector (written as lines)
  or a raw vector.

- stdout, stderr:

  Where the program's output goes: `"console"` (the R console, as it is
  written), `"capture"` (kept for `wasm_wasi_output()`), or `"discard"`.

- dirs:

  Directories the program may use, as a character vector of host paths
  named by the path the program sees them at (`c("/data" = "~/x")`). A
  single unnamed directory is seen as the program's current directory,
  so relative paths resolve inside it.

- writable:

  Whether the program may create, change and delete files in `dirs`.

- program:

  The program name the module sees as its first argument.

- instance:

  An instance created with `wasm_instantiate(wasi = )`.

- wasi:

  A `nanowasm_wasi` object.

- stream:

  Which captured stream to return.

## Value

`wasm_wasi()` returns a `nanowasm_wasi` object.

`wasm_wasi_start()` runs the program's `_start` function and returns its
exit status: 0 when `_start` returns, or the status it passed to
`exit()`. It returns invisibly when the status is 0.

`wasm_wasi_output()` returns what the program has written to a captured
stream so far, as a string.

## Details

nanowasm implements WASI itself, in R, rather than giving the program
the operating system's:

- Arguments and environment variables are only those you pass.

- Standard output and error go to the R console (or are captured or
  discarded); standard input comes from `stdin`, or is empty.

- Files are reachable only inside the directories in `dirs`, read-only
  unless `writable = TRUE`. Paths can't leave a granted directory,
  whether through `..`, absolute paths or symbolic links. Hard and
  symbolic links can't be created.

- Clocks are R's, and random numbers come from R's random number
  generator, so [`set.seed()`](https://rdrr.io/r/base/Random.html) makes
  a program's randomness reproducible.

- Sockets and signals are not available.

Functions a program calls that nanowasm doesn't provide return WASI's
`ENOSYS` or `ENOTSUP` error code, as a host without them would.

A WASI environment holds the program's open files and its output, so it
belongs to one instance; create a new one for each instance.

## See also

[`wasm_run()`](https://pedrobtz.github.io/nanowasm/reference/wasm_run.md)
to run a WASI program in one call.

## Examples

``` r
hello <- system.file("extdata", "hello-wasi.wasm", package = "nanowasm")

wasi <- wasm_wasi(args = c("from", "R"), env = c(GREETING = "Hello"))
inst <- wasm_instantiate(wasm_module(hello), wasi = wasi)
wasm_wasi_start(inst)
#> Hello from R!

# Capture the output instead.
wasi <- wasm_wasi(args = "quietly", stdout = "capture")
inst <- wasm_instantiate(wasm_module(hello), wasi = wasi)
wasm_wasi_start(inst)
wasm_wasi_output(wasi)
#> [1] "Hello quietly!\n"
```
