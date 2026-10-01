expect_trap <- function(expr, trap_id, class = "nanowasm_trap") {
  err <- expect_error(expr, class = class)
  expect_s3_class(err, "nanowasm_trap")
  expect_s3_class(err, "nanowasm_error")
  expect_identical(err$trap_id, trap_id)
  expect_type(err$detail, "character")
  invisible(err)
}

test_that("each trap maps to its trap_id and class", {
  inst <- fixture_instance("traps")
  expect_trap(inst$div_s(1L, 0L), "div_by_zero")
  expect_trap(inst$div_s(-2147483648, -1L), "integer_overflow")
  expect_trap(inst$unreachable(), "unreachable")
  expect_trap(inst$trunc(NaN), "invalid_conversion_to_integer")
  expect_trap(inst$call_null(), "call_indirect_null_funcref")
  expect_trap(
    inst$load(65536L), "out_of_bounds_memory_access",
    class = "nanowasm_out_of_bounds"
  )
  expect_trap(
    inst$call_undefined(), "call_indirect_out_of_bounds_table_access",
    class = "nanowasm_out_of_bounds"
  )
})

test_that("runaway recursion hits the frame limit instead of memory", {
  inst <- fixture_instance("traps")
  err <- expect_trap(inst$recurse(0L), "too_many_frames", class = "nanowasm_stack_exhausted")
  expect_match(conditionMessage(err), "call stack exhausted")
})

test_that("trap messages are readable", {
  inst <- fixture_instance("traps")
  expect_error(inst$div_s(1L, 0L), "WebAssembly trap in `div_s`: integer divide by zero.", fixed = TRUE)
})

test_that("an instance stays usable after a trap", {
  inst <- fixture_instance("traps")
  expect_error(inst$div_s(1L, 0L), class = "nanowasm_trap")
  expect_error(inst$recurse(0L), class = "nanowasm_trap")
  expect_identical(inst$div_s(7L, 2L), 3L)
  expect_identical(inst$load(0L), 0L)
})
