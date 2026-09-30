memory_instance <- function() fixture_instance("memory")

test_that("wasm_memory() picks the only exported memory, or one by name", {
  inst <- memory_instance()
  mem <- wasm_memory(inst)
  expect_s3_class(mem, "nanowasm_memory")
  expect_identical(mem$name, "memory")
  expect_identical(wasm_memory(inst, "memory")$index, mem$index)

  two <- fixture_instance("two-memories")
  expect_error(wasm_memory(two), "exports 2 memories")
  expect_identical(wasm_memory_size(wasm_memory(two, "b"), "pages"), 2)
  expect_identical(wasm_memory_size(wasm_memory(two, "a"), "pages"), 1)

  expect_error(wasm_memory(fixture_instance("traps")), "exports no memory")
  expect_error(wasm_memory(inst, "nope"), class = "nanowasm_argument_error")
  expect_error(wasm_memory(inst, 1), class = "nanowasm_argument_error")
  expect_error(wasm_memory(list()), class = "nanowasm_argument_error")
})

test_that("reads see what the module sees", {
  inst <- memory_instance()
  mem <- wasm_memory(inst)
  expect_identical(wasm_read(mem, 16, 5), as.integer(charToRaw("hello")))
  expect_identical(wasm_read(mem, 16, 5, "raw"), charToRaw("hello"))
  wasm_write(mem, 0, 123456789L, "i32")
  expect_identical(inst$load_i32(0L), 123456789L)
  wasm_write(mem, 8, pi, "f64")
  expect_identical(inst$load_f64(8L), pi)
})

test_that("every element type round-trips, little-endian", {
  mem <- wasm_memory(memory_instance())
  roundtrip <- function(x, type) {
    end <- wasm_write(mem, 1000, x, type)
    expect_identical(wasm_read(mem, 1000, length(x), type), x, info = type)
    end
  }
  expect_identical(roundtrip(as.raw(c(0, 1, 255)), "raw"), 1003)
  roundtrip(c(-128L, 0L, 127L), "i8")
  roundtrip(c(0L, 255L), "u8")
  roundtrip(c(-32768L, 32767L), "i16")
  roundtrip(c(0L, 65535L), "u16")
  roundtrip(c(-.Machine$integer.max, .Machine$integer.max, NA_integer_)[1:2], "i32")
  expect_identical(roundtrip(c(0, 4294967295), "u32"), 1008)
  roundtrip(c(-2^53, 2^53, -1), "i64")
  roundtrip(c(0, 2^53), "u64")
  roundtrip(c(0.5, -2, Inf), "f32")
  roundtrip(c(pi, -0, NaN, Inf), "f64")

  wasm_write(mem, 1000, 258L, "u16")
  expect_identical(wasm_read(mem, 1000, 2, "u8"), c(2L, 1L))
  wasm_write(mem, 1000, -1L, "i32")
  expect_identical(wasm_read(mem, 1000, 1, "u32"), 4294967295)
  expect_equal(wasm_read(mem, 1000, 1, "f32"), NaN)
})

test_that("f32 writes round to single precision", {
  mem <- wasm_memory(memory_instance())
  wasm_write(mem, 0, 0.1, "f32")
  expect_false(identical(wasm_read(mem, 0, 1, "f32"), 0.1))
  expect_equal(wasm_read(mem, 0, 1, "f32"), 0.1, tolerance = 1e-7)
})

test_that("writes are checked before anything changes", {
  mem <- wasm_memory(memory_instance())
  wasm_write(mem, 0, c(1L, 2L, 3L), "u8")
  expect_error(wasm_write(mem, 0, c(9L, 256L), "u8"), "Element 2 of `x` is out of range")
  expect_identical(wasm_read(mem, 0, 3), c(1L, 2L, 3L))
  expect_error(wasm_write(mem, 0, NA_integer_, "i32"), "is NA")
  expect_error(wasm_write(mem, 0, 1.5, "i16"), "not a whole number")
  expect_error(wasm_write(mem, 0, 2^53 + 2, "i64"), "out of range")
  expect_error(wasm_write(mem, 0, -1, "u64"), "out of range")
  expect_error(wasm_write(mem, 0, "a", "u8"), class = "nanowasm_argument_error")
  expect_error(wasm_write(mem, 0, 1L, "raw"), "must be a raw vector")
  expect_error(wasm_write(mem, 0, 1L, "u128"), class = "nanowasm_argument_error")
})

test_that("i64 reads that don't fit a double are errors", {
  mem <- wasm_memory(memory_instance())
  wasm_write(mem, 0, as.raw(c(rep(0xff, 7), 0x7f)), "raw")
  expect_error(wasm_read(mem, 0, 1, "i64"), class = "nanowasm_precision_error")
  expect_error(wasm_read(mem, 0, 1, "u64"), class = "nanowasm_precision_error")
})

test_that("accesses are bounds-checked", {
  mem <- wasm_memory(memory_instance())
  size <- wasm_memory_size(mem)
  expect_identical(size, 65536)
  expect_length(wasm_read(mem, size - 4, 4), 4)
  expect_length(wasm_read(mem, size, 0), 0)
  expect_error(wasm_read(mem, size - 3, 4), class = "nanowasm_out_of_bounds")
  expect_error(wasm_read(mem, size - 1, 1, "i32"), class = "nanowasm_out_of_bounds")
  expect_error(wasm_read(mem, 2^40, 1), class = "nanowasm_out_of_bounds")
  expect_error(wasm_read(mem, 0, 2^33), class = "nanowasm_out_of_bounds")
  expect_error(wasm_write(mem, size - 1, 1:2, "u8"), class = "nanowasm_out_of_bounds")
  expect_error(wasm_write(mem, 0, raw(size + 1), "raw"), class = "nanowasm_out_of_bounds")
  expect_error(wasm_read(mem, -1, 1), class = "nanowasm_argument_error")
  expect_error(wasm_read(mem, 1.5, 1), class = "nanowasm_argument_error")
  expect_error(wasm_read(mem, 0, NA), class = "nanowasm_argument_error")
})

test_that("strings are read and written as UTF-8", {
  mem <- wasm_memory(memory_instance())
  expect_identical(wasm_read_string(mem, 16), "hello")
  expect_identical(wasm_read_string(mem, 22), "world")
  expect_identical(wasm_read_string(mem, 16, 3), "hel")
  expect_identical(wasm_read_string(mem, 16, 0), "")

  x <- "héllo 世界"
  end <- wasm_write_string(mem, 200, x)
  expect_identical(end, 200 + length(charToRaw(enc2utf8(x))) + 1)
  expect_identical(wasm_read_string(mem, 200), x)
  expect_identical(Encoding(wasm_read_string(mem, 200)), "UTF-8")

  end <- wasm_write_string(mem, 300, "abc", nul = FALSE)
  expect_identical(end, 303)

  expect_error(wasm_read_string(mem, 64), "not valid UTF-8")
  expect_error(wasm_read_string(mem, 16, 11), "NUL byte")
  expect_error(wasm_write_string(mem, 0, c("a", "b")), class = "nanowasm_argument_error")
  expect_error(wasm_write_string(mem, 0, NA_character_), class = "nanowasm_argument_error")
})

test_that("a string running to the end of memory has no terminator", {
  mem <- wasm_memory(memory_instance())
  size <- wasm_memory_size(mem)
  wasm_write(mem, size - 3, as.raw(c(0x61, 0x62, 0x63)), "raw")
  expect_error(wasm_read_string(mem, size - 3), class = "nanowasm_out_of_bounds")
  expect_error(wasm_read_string(mem, size), class = "nanowasm_out_of_bounds")
})

test_that("memory grows up to its maximum, from R or from Wasm", {
  inst <- memory_instance()
  mem <- wasm_memory(inst)
  expect_identical(wasm_memory_grow(mem, 1), 1)
  expect_identical(wasm_memory_size(mem, "pages"), 2)
  expect_identical(inst$grow(1L), 2L)
  expect_identical(wasm_memory_size(mem), 3 * 65536)
  expect_error(wasm_memory_grow(mem, 2), class = "nanowasm_memory_limit")
  expect_identical(inst$grow(2L), -1L)
  expect_identical(wasm_memory_grow(mem, 0), 3)
  expect_error(wasm_memory_grow(mem, -1), class = "nanowasm_argument_error")
})

test_that("memory handles print and outlive their instance variable", {
  mem <- wasm_memory(memory_instance())
  gc()
  expect_identical(wasm_read_string(mem, 16), "hello")
  expect_snapshot(print(mem))
  expect_error(wasm_read(list(), 0, 1), class = "nanowasm_argument_error")
})

test_that("memory handles of saved instances are invalid", {
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path))
  saveRDS(wasm_memory(memory_instance()), path)
  mem <- readRDS(path)
  expect_identical(format(mem), "<nanowasm_memory> (invalid)")
  expect_error(wasm_read(mem, 0, 1), class = "nanowasm_invalid_object")
})

test_that("the sum example works end to end", {
  inst <- wasm_instantiate(wasm_module(system.file("extdata", "sum.wasm", package = "nanowasm")))
  mem <- wasm_memory(inst)
  x <- runif(10000)
  ptr <- inst$alloc(8L * length(x))
  wasm_write(mem, ptr, x, "f64")
  expect_equal(inst$sum_f64(ptr, length(x)), sum(x))
  expect_gt(wasm_memory_size(mem, "pages"), 1)
})
