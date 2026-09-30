test_that("wasm_limits() validates and prints", {
  lim <- wasm_limits()
  expect_s3_class(lim, "nanowasm_limits")
  expect_identical(lim$memory, 256 * 2^20)
  expect_identical(lim$timeout, Inf)
  expect_snapshot(print(wasm_limits()))
  expect_snapshot(print(wasm_limits(memory = Inf, frames = 100, stack = 5000, timeout = 1.5)))

  expect_error(wasm_limits(memory = -1), class = "nanowasm_argument_error")
  expect_error(wasm_limits(frames = Inf), class = "nanowasm_argument_error")
  expect_error(wasm_limits(frames = 1.5), class = "nanowasm_argument_error")
  expect_error(wasm_limits(stack = NA), class = "nanowasm_argument_error")
  expect_error(wasm_limits(timeout = 0), class = "nanowasm_argument_error")
  expect_error(wasm_limits(timeout = "1"), class = "nanowasm_argument_error")
  expect_error(
    wasm_instantiate(wasm_module(fixture("start")), limits = list()),
    class = "nanowasm_argument_error"
  )
})

test_that("an infinite loop stops at the timeout", {
  inst <- wasm_instantiate(wasm_module(fixture("hostile")), limits = wasm_limits(timeout = 0.2))
  elapsed <- system.time(
    err <- expect_error(inst$spin(), class = "nanowasm_timeout")
  )[["elapsed"]]
  expect_gte(err$elapsed, 0.2)
  expect_identical(err$limit, 0.2)
  expect_lt(elapsed, 5)
  expect_identical(inst$grow_and_touch(0L), 1L)
})

test_that("the timeout covers the start function", {
  expect_error(
    wasm_instantiate(wasm_module(fixture("start-spin")), limits = wasm_limits(timeout = 0.2)),
    class = "nanowasm_timeout"
  )
})

test_that("the nanowasm.limits option sets the default", {
  old <- options(nanowasm.limits = wasm_limits(timeout = 0.2))
  on.exit(options(old))
  inst <- wasm_instantiate(wasm_module(fixture("hostile")))
  expect_error(inst$spin(), class = "nanowasm_timeout")
})

test_that("memory growth stops at the memory limit", {
  limits <- wasm_limits(memory = 16 * 2^20)
  inst <- wasm_instantiate(wasm_module(fixture("hostile")), limits = limits)
  pages <- inst$grow_until_fail()
  expect_lte((pages + 1) * 65536, 16 * 2^20)
  expect_gt(pages, 200)
  expect_identical(inst$table_grow(1e8), -1L)

  inst <- wasm_instantiate(wasm_module(fixture("hostile")), limits = limits)
  expect_identical(inst$grow_and_touch(1000L), -1L)
  expect_identical(inst$grow_and_touch(10L), 11L)
  expect_error(wasm_memory_grow(wasm_memory(inst), 1000), class = "nanowasm_memory_limit")
})

test_that("instantiation fails cleanly past the memory limit", {
  expect_error(wasm_instantiate(wasm_module(fixture("big-table"))), "memory limit was exceeded")
  expect_error(wasm_instantiate(wasm_module(fixture("big-table"))), class = "nanowasm_memory_limit")
})

test_that("recursion stops at the frame or stack-cell limit", {
  mod <- wasm_module(fixture("traps"))
  inst <- wasm_instantiate(mod, limits = wasm_limits(frames = 100))
  err <- expect_error(inst$recurse(0L), class = "nanowasm_stack_exhausted")
  expect_identical(err$trap_id, "too_many_frames")

  inst <- wasm_instantiate(mod, limits = wasm_limits(frames = 1e6, stack = 1000))
  err <- expect_error(inst$deep_stack(0L), class = "nanowasm_stack_exhausted")
  expect_identical(err$trap_id, "too_many_stackcells")
  expect_match(conditionMessage(err), "value stack exhausted")
})

test_that("R stays usable after every limit", {
  inst <- wasm_instantiate(
    wasm_module(fixture("hostile")),
    limits = wasm_limits(memory = 8 * 2^20, timeout = 0.1)
  )
  expect_error(inst$spin(), class = "nanowasm_timeout")
  expect_identical(inst$grow_until_fail() > 0, TRUE)
  expect_error(inst$spin(), class = "nanowasm_timeout")
  expect_identical(fixture_instance("start")$get(), 7L)
})

test_that("Ctrl-C interrupts a running call", {
  skip_if_signals_unreliable()
  # The timeout is only a backstop, so a broken interrupt fails rather than
  # hangs.
  inst <- wasm_instantiate(wasm_module(fixture("hostile")), limits = wasm_limits(timeout = 10))
  system2("sh", c("-c", shQuote(sprintf("sleep 0.5; kill -INT %d", Sys.getpid()))), wait = FALSE)
  res <- tryCatch(inst$spin(), interrupt = function(cnd) cnd)
  expect_s3_class(res, "interrupt")
  expect_identical(inst$grow_and_touch(0L), 1L)
})
