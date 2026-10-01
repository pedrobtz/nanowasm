backtrace_instance <- function(check = function(x) NULL) {
  wasm_instantiate(
    wasm_module(fixture("backtrace")),
    imports = list(env = list(check = wasm_func(check, "i32")))
  )
}

test_that("a trap names its function and carries the call stack", {
  inst <- backtrace_instance()
  expect_identical(inst$run(5L), 21L)
  err <- expect_error(inst$run(0L), class = "nanowasm_trap")
  expect_identical(conditionMessage(err), "WebAssembly trap in `inner`: integer divide by zero.")
  expect_identical(err$func, "inner")
  expect_identical(err$backtrace, c("inner", "middle", "outer"))
  expect_identical(err$depth, 3)
  expect_identical(err$trap_id, "div_by_zero")
})

test_that("deep stacks keep the innermost 64 frames and the full depth", {
  inst <- backtrace_instance()
  err <- expect_error(inst$deep(100L), class = "nanowasm_trap")
  expect_identical(err$depth, 101)
  expect_length(err$backtrace, 64)
  expect_identical(unique(err$backtrace), "deep")

  traps <- wasm_instantiate(wasm_module(fixture("traps")), limits = wasm_limits(frames = 50))
  err <- expect_error(traps$recurse(0L), class = "nanowasm_stack_exhausted")
  expect_identical(err$depth, 50)
  expect_match(conditionMessage(err), "^WebAssembly trap in `recurse`: call stack exhausted")
})

test_that("without a name section, export names or indices are used", {
  inst <- fixture_instance("nameless")
  err <- expect_error(inst$run(0L), class = "nanowasm_trap")
  expect_identical(err$backtrace, c("func[0]", "func[1]", "run"))
  expect_identical(err$func, "func[0]")
})

test_that("errors in imports and timeouts carry the WebAssembly stack", {
  inst <- backtrace_instance(function(x) if (x > 3) stop("too big"))
  inst$report(1L)
  err <- expect_error(inst$report(9L), class = "nanowasm_host_error")
  expect_identical(err$backtrace, "report")
  expect_identical(conditionMessage(err$parent), "too big")

  hostile <- wasm_instantiate(wasm_module(fixture("hostile")), limits = wasm_limits(timeout = 0.1))
  err <- expect_error(hostile$spin(), class = "nanowasm_timeout")
  expect_identical(err$func, "spin")
})

test_that("a trap in a start function has a backtrace too", {
  err <- expect_error(fixture_instance("start-trap"), class = "nanowasm_trap")
  expect_identical(err$depth, 1)
  expect_identical(err$func, "func[0]")
})
