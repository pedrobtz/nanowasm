# Examples

A tour of what you can do with nanowasm, one small module at a time.
Each module is a few dozen lines of the WebAssembly text format,
compiled with `wat2wasm`; the sources are in
[`vignettes/articles/wasm/`](https://github.com/pedrobtz/nanowasm/tree/main/vignettes/articles/wasm)
in the package’s repository.
[`vignette("nanowasm")`](https://pedrobtz.github.io/nanowasm/articles/nanowasm.md)
covers the API itself.

``` r

library(nanowasm)

# Load one of this article's modules.
example_module <- function(name) {
  wasm_module(file.path("wasm", paste0(name, ".wasm")))
}
```

## Strings through linear memory

WebAssembly functions only take numbers, so text travels through the
module’s memory: R writes the bytes, passes a pointer and a length, and
reads the result back. `strings.wasm` works on bytes in place:

``` r

strings <- wasm_instantiate(example_module("strings"))
mem <- wasm_memory(strings)

text <- "hello from R, via WebAssembly"
len <- length(charToRaw(text))
wasm_write_string(mem, 0, text, nul = FALSE)

strings$count(0L, len, utf8ToInt("o"))
#> [1] 2
strings$upper(0L, len)
wasm_read_string(mem, 0, len)
#> [1] "HELLO FROM R, VIA WEBASSEMBLY"
```

Offset 0 is fine here because the module doesn’t use its memory for
anything else. A real module usually exports an allocator; see the
`sum.wasm` example in
[`vignette("nanowasm")`](https://pedrobtz.github.io/nanowasm/articles/nanowasm.md).

## An image computed in WebAssembly

`mandelbrot.wasm` renders the Mandelbrot set into its memory, one byte
per pixel holding the number of iterations before the point escaped. R
reads the bytes back as a matrix and plots it:

``` r

mandel <- wasm_instantiate(example_module("mandelbrot"))
w <- 240L
h <- 180L
maxiter <- 64L

mandel$render(0L, w, h, -2.4, -1.2, 0.9, 1.2, maxiter)
iterations <- wasm_read(wasm_memory(mandel), 0, w * h, "u8")
img <- matrix(iterations, nrow = w)

op <- par(mar = c(0, 0, 0, 0))
# Points that never escaped (the set itself) are black.
colours <- c(hcl.colors(maxiter, "Inferno"), "black")
image(img, col = colours, axes = FALSE, useRaster = TRUE)
```

![](examples_files/figure-html/mandelbrot-1.png)

``` r

par(op)
```

The module does all the arithmetic; R only handles the finished
43200-byte image.

## Calling R from WebAssembly

A module can import functions from its host. `integrate.wasm` implements
the trapezoidal rule for an imported `math.f`, so R decides what to
integrate:

``` r

wasm_imports(example_module("integrate"))
#>   module name     kind         type
#> 1   math    f function (f64) -> f64

integrator <- function(f) {
  wasm_instantiate(
    example_module("integrate"),
    imports = list(math = list(f = wasm_func(f, params = "f64", results = "f64")))
  )
}

integrator(sin)$trapezoid(0, pi, 1000L)
#> [1] 1.999998
integrator(dnorm)$trapezoid(-1.96, 1.96, 1000L)
#> [1] 0.9500039
```

The imported function can be any R closure, including one that keeps
state. Here it counts how often WebAssembly called back into R:

``` r

calls <- 0
counted_exp <- function(x) {
  calls <<- calls + 1
  exp(-x^2)
}
integrator(counted_exp)$trapezoid(-3, 3, 200L)
#> [1] 1.772415
calls
#> [1] 201
```

If the R function fails, the WebAssembly call stops and the error
carries the original condition:

``` r

picky <- integrator(function(x) if (x > 1) stop("x is too large") else x)
err <- tryCatch(picky$trapezoid(0, 2, 10L), nanowasm_host_error = identity)
conditionMessage(err)
#> [1] "The R function imported as `math.f` failed: x is too large"
conditionMessage(err$parent)
#> [1] "x is too large"
```

## State lives in the instance

A module is code; an instance is that code with its own memory and
globals. Instances of the same module don’t share state:

``` r

counter <- example_module("counter")
a <- wasm_instantiate(counter)
b <- wasm_instantiate(counter)

for (i in 1:3) a$tick()
b$tick()
#> [1] 1

c(a = wasm_global(a, "count"), b = wasm_global(b, "count"))
#> a b 
#> 3 1

wasm_global(b, "count") <- 100L
b$tick()
#> [1] 101
```

## A command-line program, via WASI

Programs written for an operating system, rather than as libraries, run
through WASI. `wc.wasm` is a small `wc` (line, word and byte counts)
written in C and compiled with wasi-sdk; its source is next to it.
[`wasm_run()`](https://pedrobtz.github.io/nanowasm/reference/wasm_run.md)
gives it standard input, arguments and only the directories you grant:

``` r

wc <- example_module("wc")

# Standard input.
wasm_run(wc, stdin = c("the quick brown fox", "jumps over the lazy dog"))$stdout
#> [1] "      2       9      44 \n"

# Files in a directory the program is allowed to read.
docs <- file.path(tempdir(), "docs")
dir.create(docs, showWarnings = FALSE)
writeLines(c("one", "two words", "three more words"), file.path(docs, "a.txt"))
writeLines(rep("lorem ipsum", 100), file.path(docs, "b.txt"))
res <- wasm_run(wc, args = c("a.txt", "b.txt"), dirs = docs)
cat(res$stdout)
#>       3       6      31 a.txt
#>     100     200    1200 b.txt
#>     103     206    1231 total
```

Anything outside the granted directory doesn’t exist as far as the
program is concerned:

``` r

wasm_run(wc, args = c("a.txt", "../../etc/passwd"), dirs = docs)
#> <nanowasm_run> exit status 1
#> -- stdout --
#>       3       6      31 a.txt
#>       3       6      31 total
#> -- stderr --
#> wc: ../../etc/passwd: Capabilities insufficient
```

## Running code you don’t trust

`untrusted.wasm` loops forever, recurses without end and grabs all the
memory it can. Under
[`wasm_limits()`](https://pedrobtz.github.io/nanowasm/reference/wasm_limits.md)
each of those ends in an error of its own class, and R carries on:

``` r

untrusted <- wasm_instantiate(
  example_module("untrusted"),
  limits = wasm_limits(memory = 16 * 2^20, frames = 1000, timeout = 0.25)
)

run_safely <- function(expr) {
  tryCatch(
    expr,
    nanowasm_timeout = function(e) "stopped: time limit",
    nanowasm_stack_exhausted = function(e) "stopped: stack limit",
    nanowasm_memory_limit = function(e) "stopped: memory limit",
    nanowasm_trap = function(e) paste("trapped:", e$trap_id)
  )
}

run_safely(untrusted$spin())
#> [1] "stopped: time limit"
run_safely(untrusted$recurse(0L))
#> [1] "stopped: stack limit"
```

A module asking for more memory than the limit allows is told no, as
WebAssembly specifies (`memory.grow` returns -1), so `hog()` stops
growing at the limit and returns the number of pages it managed to get:

``` r

pages <- untrusted$hog()
pages
#> [1] 255
pages * 65536 / 2^20 # MiB
#> [1] 15.9375
```

The instance is still usable after all of this:

``` r

run_safely(untrusted$spin())
#> [1] "stopped: time limit"
```
