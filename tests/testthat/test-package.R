test_that("the bundled toywasm is the vendored version", {
  expect_identical(toywasm_version(), "v76.0.0")
})
