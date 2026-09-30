test_that("the start function runs at instantiation", {
  expect_identical(fixture_instance("start")$get(), 7L)
})

test_that("a trapping start function fails instantiation", {
  expect_error(fixture_instance("start-trap"), class = "nanowasm_trap")
})

test_that("modules with imports can't be instantiated yet", {
  err <- expect_error(fixture_instance("imports"), class = "nanowasm_link_error")
  expect_identical(err$missing$name, c("log", "mem", "g", "tbl"))
  expect_match(conditionMessage(err), "`env.log`, `env.mem`, `js.g`, `js.tbl`")
})

test_that("wasm_instantiate() needs a module", {
  expect_error(wasm_instantiate(list()), class = "nanowasm_argument_error")
})

test_that("a module can be instantiated many times, independently", {
  mod <- wasm_module(fixture("start"))
  insts <- lapply(1:20, function(i) wasm_instantiate(mod))
  expect_identical(vapply(insts, function(i) i$get(), 1L), rep(7L, 20))
})
