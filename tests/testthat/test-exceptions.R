test_that("WebAssembly code throws, catches and rethrows exceptions", {
  inst <- fixture_instance("exceptions")
  expect_identical(inst$catch_it(5L), 5L)
  expect_identical(inst$catch_it(0L), -1L)
  expect_identical(inst$catch_all(), 99L)
  expect_identical(inst$rethrow(8L), 8L)
})

test_that("an exception escaping an export is a trap", {
  inst <- fixture_instance("exceptions")
  err <- expect_error(inst$uncaught(3L), class = "nanowasm_trap")
  expect_identical(err$trap_id, "uncaught_exception")
  expect_match(conditionMessage(err), "uncaught exception")
  expect_identical(err$backtrace[[length(err$backtrace)]], "uncaught")
  # The instance is still usable.
  expect_identical(inst$catch_it(2L), 2L)
})

test_that("exception tags are listed with what they carry", {
  ex <- wasm_exports(wasm_module(fixture("exceptions")))
  expect_identical(unlist(ex[ex$name == "oops", c("kind", "type")], use.names = FALSE), c("tag", "(i32)"))
})

test_that("C setjmp/longjmp works", {
  res <- wasm_run(test_path("fixtures", "wasi", "setjmp.wasm"))
  expect_identical(res$status, 0L)
  expect_identical(
    res$stdout,
    "first pass\nlongjmp returned 42\nlongjmp(env, 0) returned 1\n"
  )
})

test_that("C++ exceptions unwind, are caught and rethrown", {
  res <- wasm_run(test_path("fixtures", "wasi", "exceptions.wasm"))
  expect_identical(res$status, 0L)
  expect_identical(
    res$stdout,
    paste0(
      "unwound fail\ncaught std::exception: negative\n",
      "unwound fail\nrethrowing\ncaught Problem 7\n"
    )
  )
  expect_error(
    wasm_run(test_path("fixtures", "wasi", "exceptions.wasm"), args = "uncaught"),
    class = "nanowasm_trap"
  )
})

test_that("the legacy exception encoding is refused with a hint", {
  err <- expect_error(
    wasm_module(test_path("fixtures", "wasi", "legacy-eh.wasm")),
    class = "nanowasm_validation_error"
  )
  expect_match(conditionMessage(err), "legacy encoding of WebAssembly exceptions")
  expect_match(conditionMessage(err), "-wasm-use-legacy-eh=false", fixed = TRUE)
  # Other validation errors don't get the hint.
  expect_no_match(conditionMessage(expect_error(wasm_module(as.raw(1:8)))), "legacy")
})

test_that("tags can't be imported", {
  bytes <- as.raw(c(
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, # magic, version
    0x01, 0x04, 0x01, 0x60, 0x00, 0x00,             # type section: () -> ()
    0x02, 0x0c, 0x01, 0x03, 0x65, 0x6e, 0x76,       # import section (12 bytes): env
    0x03, 0x74, 0x61, 0x67, 0x04, 0x00, 0x00        #   "tag", tag of type 0
  ))
  mod <- wasm_module(bytes)
  expect_identical(wasm_imports(mod)$kind, "tag")
  expect_error(wasm_instantiate(mod), "importing tags is not supported")
})
