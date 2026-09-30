# Access an instance's linear memory

`wasm_memory()` returns a handle to one of an instance's exported
memories. `wasm_read()` and `wasm_write()` copy vectors out of and into
it, and `wasm_read_string()` and `wasm_write_string()` do the same for
UTF-8 strings. `wasm_memory_size()` and `wasm_memory_grow()` query and
change its size.

## Usage

``` r
wasm_memory(instance, name = NULL)

wasm_read(memory, offset, n, type = "u8")

wasm_write(memory, offset, x, type = "u8")

wasm_read_string(memory, offset, n = NULL)

wasm_write_string(memory, offset, x, nul = TRUE)

wasm_memory_size(memory, unit = c("bytes", "pages"))

wasm_memory_grow(memory, pages)
```

## Arguments

- instance:

  A `nanowasm_instance`.

- name:

  The export name of the memory. The default, `NULL`, picks the
  instance's only exported memory.

- memory:

  A `nanowasm_memory` from `wasm_memory()`.

- offset:

  Byte offset (0-based).

- n:

  Number of elements to read. For `wasm_read_string()`, the number of
  bytes, or `NULL` to read up to the first NUL byte.

- type:

  Element type; see Details.

- x:

  For `wasm_write()`, the vector to write. For `wasm_write_string()`, a
  single string.

- nul:

  Whether to write a terminating NUL byte after the string.

- unit:

  Report the size in `"bytes"` or in `"pages"` (64 KiB each).

- pages:

  Number of pages to add.

## Value

`wasm_memory()` returns a `nanowasm_memory`. `wasm_read()` returns a
vector of length `n` and `wasm_read_string()` a string. `wasm_write()`
and `wasm_write_string()` invisibly return the offset just past the
bytes written. `wasm_memory_size()` returns a number, and
`wasm_memory_grow()` the previous size in pages.

## Details

Offsets are 0-based byte addresses, the same numbers a WebAssembly
function receives as pointers, not 1-based R indices. Every access is
checked against the memory's current size; one that falls outside
signals a `nanowasm_out_of_bounds` error and changes nothing.

`type` gives the element type, stored little-endian as WebAssembly
requires:

|  |  |  |
|----|----|----|
| `type` | R vector | Notes |
| `"raw"` | raw |  |
| `"i8"`, `"u8"`, `"i16"`, `"u16"`, `"i32"` | integer |  |
| `"u32"` | double |  |
| `"i64"`, `"u64"` | double | Values beyond \\2^{53}\\ signal a `nanowasm_precision_error`. |
| `"f32"`, `"f64"` | double | `f32` values are rounded to single precision. |

Writes check every element before changing any memory: integer types
reject `NA`, fractions and values outside the type's range.

WebAssembly has no standard allocator. To pass data to a function, use
the module's own allocation export (often named `malloc` or `alloc`) to
get an offset, then write there.

## Examples

``` r
mod <- wasm_module(system.file("extdata", "sum.wasm", package = "nanowasm"))
inst <- wasm_instantiate(mod)
mem <- wasm_memory(inst)
mem
#> <nanowasm_memory> `memory`: 1 page (64 KiB)

# Ask the module for room for 5 doubles, fill it, and sum it.
x <- c(1.5, 2.5, 3, 4, 5)
ptr <- inst$alloc(8L * length(x))
wasm_write(mem, ptr, x, "f64")
inst$sum_f64(ptr, length(x))
#> [1] 16
wasm_read(mem, ptr, 5, "f64")
#> [1] 1.5 2.5 3.0 4.0 5.0

next_free <- wasm_write_string(mem, 1024, "héllo")
wasm_read_string(mem, 1024)
#> [1] "héllo"
wasm_read(mem, 1024, next_free - 1024, "u8")
#> [1] 104 195 169 108 108 111   0
```
