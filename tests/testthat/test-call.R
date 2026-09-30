test_that("i32 maps to integer, including unsigned bit patterns and NA", {
  inst <- fixture_instance("types")
  expect_identical(inst$add(1L, 2L), 3L)
  expect_identical(inst$add(2, 3), 5L)
  expect_identical(inst$id_i32(-2147483648), NA_integer_)
  expect_identical(inst$id_i32(NA_integer_), NA_integer_)
  expect_identical(inst$id_i32(2147483648), NA_integer_)
  expect_identical(inst$id_i32(4294967295), -1L)
  expect_identical(inst$add(.Machine$integer.max, 1L), NA_integer_)
})

test_that("i32 arguments are range- and type-checked", {
  inst <- fixture_instance("types")
  expect_error(inst$id_i32(4294967296), class = "nanowasm_argument_error")
  expect_error(inst$id_i32(-2147483649), class = "nanowasm_argument_error")
  expect_error(inst$id_i32(1.5), class = "nanowasm_argument_error")
  expect_error(inst$id_i32(NaN), class = "nanowasm_argument_error")
  expect_error(inst$id_i32(Inf), class = "nanowasm_argument_error")
  expect_error(inst$id_i32(TRUE), class = "nanowasm_argument_error")
  expect_error(inst$id_i32("1"), class = "nanowasm_argument_error")
  expect_error(inst$id_i32(1:2), class = "nanowasm_argument_error")
  expect_error(inst$id_i32(integer()), class = "nanowasm_argument_error")
})

test_that("i64 maps to double within 2^53", {
  inst <- fixture_instance("types")
  expect_identical(inst$id_i64(2^53), 2^53)
  expect_identical(inst$id_i64(-2^53), -2^53)
  expect_identical(inst$id_i64(5L), 5)
  expect_identical(inst$i64_2p53(), 2^53)
  expect_error(inst$id_i64(2^53 + 2), class = "nanowasm_argument_error")
  expect_error(inst$id_i64(0.5), class = "nanowasm_argument_error")
  expect_error(inst$id_i64(NA_integer_), class = "nanowasm_argument_error")
  expect_error(inst$id_i64(NA_real_), class = "nanowasm_argument_error")
})

test_that("i64 results a double can't hold signal nanowasm_precision_error", {
  inst <- fixture_instance("types")
  expect_error(inst$i64_2p53_plus_1(), class = "nanowasm_precision_error")
  expect_error(inst$i64_min(), class = "nanowasm_precision_error")
  expect_error(inst$i64_min(), "-9223372036854775808")
})

test_that("f32 and f64 map to double", {
  inst <- fixture_instance("types")
  expect_identical(inst$id_f64(0.1), 0.1)
  expect_identical(inst$id_f64(-0), -0)
  expect_identical(1 / inst$id_f64(-0), -Inf)
  expect_identical(inst$id_f64(Inf), Inf)
  expect_true(is.nan(inst$id_f64(NaN)))
  expect_true(is.na(inst$id_f64(NA_real_)))
  expect_true(is.na(inst$id_f64(NA_integer_)))
  expect_identical(inst$id_f64(3L), 3)
  expect_equal(inst$id_f32(0.1), 0.1, tolerance = 1e-7)
  expect_false(identical(inst$id_f32(0.1), 0.1))
  expect_identical(inst$id_f32(3L), 3)
  expect_true(is.nan(inst$id_f32(NA_integer_)))
  expect_identical(inst$id_f32(1e300), Inf)
})

test_that("results come back as a scalar, a list or invisible NULL", {
  inst <- fixture_instance("types")
  expect_identical(inst$swap(3L, 5), list(5, 3L))
  expect_null(inst$nothing())
  expect_invisible(inst$nothing())
})

test_that("arity is checked", {
  inst <- fixture_instance("types")
  expect_error(inst$add(1L), "takes 2 arguments but was given 1")
  expect_error(inst$add(1L, 2L, 3L), class = "nanowasm_argument_error")
  expect_error(inst$nothing(1L), "takes 0 arguments")
  expect_error(inst$id_i32(), "takes 1 argument but")
})

test_that("reference types are rejected at the boundary", {
  inst <- fixture_instance("types")
  expect_error(inst$takes_funcref(), class = "nanowasm_unsupported")
  expect_error(inst$returns_externref(), class = "nanowasm_unsupported")
})

test_that("wasm_call() and `$` / `[[` are equivalent", {
  inst <- fixture_instance("types")
  expect_identical(wasm_call(inst, "add", 1L, 2L), 3L)
  expect_identical(inst[["add"]](1L, 2L), 3L)
  add <- inst$add
  expect_identical(add(4L, 5L), 9L)
})

test_that("unknown names and non-function exports are errors", {
  inst <- fixture_instance("types")
  expect_error(inst$nope, class = "nanowasm_argument_error")
  expect_error(inst$memory, "is a memory, not a function")
  expect_error(wasm_call(inst, "memory"), class = "nanowasm_argument_error")
  expect_error(wasm_call(inst, "nope"), "no exported function named `nope`")
  expect_error(wasm_call(inst, c("a", "b")), class = "nanowasm_argument_error")
  expect_error(wasm_call(inst, NA_character_), class = "nanowasm_argument_error")
  expect_error(wasm_call(list(), "add"), class = "nanowasm_argument_error")
})

test_that("errors report the user's call", {
  inst <- fixture_instance("types")
  err <- tryCatch(inst$add(1L), error = identity)
  expect_identical(deparse(conditionCall(err)), "inst$add(1L)")
  err <- tryCatch(inst$nope, error = identity)
  expect_identical(deparse(conditionCall(err)), "inst$nope")
  err <- tryCatch(wasm_call(inst, "add"), error = identity)
  expect_identical(deparse(conditionCall(err)), 'wasm_call(inst, "add")')
})

test_that("instances list their exports and can't be modified", {
  inst <- fixture_instance("types")
  expect_identical(names(inst), wasm_exports(inst)$name)
  expect_error(inst$add <- 1, class = "nanowasm_argument_error")
  expect_error(inst[["add"]] <- 1, class = "nanowasm_argument_error")
  expect_snapshot(print(fixture_instance("start")))
})

test_that("fib runs from the bundled example", {
  mod <- wasm_module(system.file("extdata", "fib.wasm", package = "nanowasm"))
  expect_identical(wasm_instantiate(mod)$fib(25L), 75025L)
})
