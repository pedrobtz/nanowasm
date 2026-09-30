test_that("an instance keeps its module alive", {
  inst <- local({
    mod <- wasm_module(fixture("start"))
    wasm_instantiate(mod)
  })
  gc()
  expect_identical(inst$get(), 7L)
})

test_that("modules and instances can be collected in any order", {
  for (i in 1:50) {
    mod <- wasm_module(fixture("start"))
    inst <- wasm_instantiate(mod)
    if (i %% 2 == 0) rm(mod) else rm(inst)
    gc()
  }
  rm(list = intersect(c("mod", "inst"), ls()))
  gc()
  expect_identical(fixture_instance("start")$get(), 7L)
})

test_that("saved and restored objects signal nanowasm_invalid_object", {
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path))
  inst <- fixture_instance("types")
  saveRDS(inst, path)
  restored <- readRDS(path)
  expect_error(restored$add(1L, 2L), class = "nanowasm_invalid_object")
  expect_error(restored$add(1L, 2L), "no longer valid")

  saveRDS(wasm_module(fixture("types")), path)
  expect_error(wasm_instantiate(readRDS(path)), class = "nanowasm_invalid_object")
})

test_that("calls survive gctorture", {
  skip_on_cran()
  inst <- fixture_instance("types")
  gctorture(TRUE)
  on.exit(gctorture(FALSE))
  res <- inst$swap(3L, 5)
  gctorture(FALSE)
  expect_identical(res, list(5, 3L))
})
