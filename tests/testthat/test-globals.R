test_that("exported globals can be read, and mutable ones set", {
  inst <- fixture_instance("types")
  expect_identical(wasm_global(inst, "counter"), 0L)
  expect_identical(wasm_global(inst, "answer"), 42)
  wasm_global(inst, "counter") <- 5L
  expect_identical(wasm_global(inst, "counter"), 5L)
  wasm_global(inst, "counter") <- 4294967295
  expect_identical(wasm_global(inst, "counter"), -1L)
})

test_that("globals are checked by name, mutability and type", {
  inst <- fixture_instance("types")
  expect_error(wasm_global(inst, "nope"), "no exported global named `nope`")
  expect_error(wasm_global(inst, "add"), class = "nanowasm_argument_error")
  expect_error(wasm_global(inst, "answer") <- 1, "is immutable")
  expect_error(wasm_global(inst, "counter") <- 1.5, "The value for `counter`")
  expect_error(wasm_global(inst, "counter") <- "a", class = "nanowasm_argument_error")
  expect_error(wasm_global(list(), "counter"), class = "nanowasm_argument_error")
  expect_error(wasm_global(inst, 1), class = "nanowasm_argument_error")
})

test_that("the sum example's heap pointer is a global", {
  inst <- wasm_instantiate(wasm_module(system.file("extdata", "sum.wasm", package = "nanowasm")))
  expect_identical(wasm_global(inst, "heap_top"), 1024L)
  expect_identical(inst$alloc(10L), 1024L)
  expect_identical(wasm_global(inst, "heap_top"), 1034L)
  expect_identical(inst$alloc(8L), 1040L)
})
