test_that("wasm_stats() counts runs, calls and branches", {
  inst <- wasm_instantiate(wasm_module(system.file("extdata", "fib.wasm", package = "nanowasm")))
  s0 <- wasm_stats(inst)
  expect_s3_class(s0, "nanowasm_stats")
  expect_named(s0, c("memory", "memory_peak", "memory_limit", "runs", "calls", "host_calls", "branches"))
  expect_identical(s0$runs, 1) # instantiation (data and element segments)
  expect_identical(s0$calls, 0)

  inst$fib(10L)
  s1 <- wasm_stats(inst)
  expect_identical(s1$runs, 2)
  # fib(n) makes 2 * fib(n + 1) - 1 calls: fib(11) = 89.
  expect_identical(s1$calls - s0$calls, 2 * 89 - 1)
  expect_identical(s1$host_calls, 0)
  expect_gt(s1$branches, s0$branches)

  inst$fib(10L)
  expect_identical(wasm_stats(inst)$calls - s1$calls, 2 * 89 - 1)
  expect_identical(wasm_stats(inst)$runs, 3)
})

test_that("failed and trapped runs are counted too", {
  inst <- fixture_instance("traps")
  before <- wasm_stats(inst)$runs
  expect_error(inst$unreachable(), class = "nanowasm_trap")
  expect_error(inst$recurse(0L), class = "nanowasm_stack_exhausted")
  s <- wasm_stats(inst)
  expect_identical(s$runs - before, 2)
  expect_gte(s$calls, 10000)
})

test_that("host calls are counted", {
  calls <- 0
  inst <- wasm_instantiate(
    wasm_module(fixture("host")),
    imports = list(
      env = list(
        add = wasm_func(function(a, b) {
          calls <<- calls + 1
          a + b
        }, c("i32", "i32"), "i32"),
        pair = wasm_func(function() list(1, 2), results = c("i64", "f64")),
        effect = wasm_func(function() NULL)
      ),
      math = list(twice = wasm_func(function(x) 2 * x, "i64", "i64"))
    )
  )
  inst$sum_adds(25L)
  s <- wasm_stats(inst)
  expect_identical(s$host_calls, 25)
  expect_identical(calls, 25)
  expect_gte(s$calls, 26)
})

test_that("memory tracks growth, the peak and the limit", {
  inst <- wasm_instantiate(
    wasm_module(fixture("hostile")),
    limits = wasm_limits(memory = 16 * 2^20)
  )
  s0 <- wasm_stats(inst)
  expect_identical(s0$memory_limit, 16 * 2^20)
  inst$grow_and_touch(10L)
  s1 <- wasm_stats(inst)
  expect_gt(s1$memory, s0$memory + 10 * 65536)
  expect_gte(s1$memory_peak, s1$memory)
  expect_lte(s1$memory, s1$memory_limit)

  unlimited <- wasm_instantiate(wasm_module(fixture("start")), limits = wasm_limits(memory = Inf))
  expect_identical(wasm_stats(unlimited)$memory_limit, Inf)
})

test_that("stats print and check their argument", {
  inst <- wasm_instantiate(wasm_module(system.file("extdata", "fib.wasm", package = "nanowasm")))
  inst$fib(5L)
  out <- format(wasm_stats(inst))
  expect_match(out[[1]], "<nanowasm_stats>")
  expect_match(out[[2]], "limit 256 MiB")
  expect_match(out[[4]], "calls: +15 \\(0 to imports\\)")
  expect_output(print(wasm_stats(inst)), "branches")
  expect_error(wasm_stats(list()), class = "nanowasm_argument_error")
})
