test_that("modules load from a path or a raw vector", {
  path <- fixture("types")
  from_path <- wasm_module(path)
  from_raw <- wasm_module(readBin(path, "raw", file.size(path)))
  expect_s3_class(from_path, "nanowasm_module")
  expect_identical(wasm_exports(from_path), wasm_exports(from_raw))
})

test_that("invalid modules signal nanowasm_validation_error", {
  expect_error(wasm_module(as.raw(1:8)), class = "nanowasm_validation_error")
  expect_error(wasm_module(raw()), class = "nanowasm_validation_error")

  bytes <- readBin(fixture("types"), "raw", file.size(fixture("types")))
  truncated <- bytes[seq_len(length(bytes) - 5)]
  expect_error(wasm_module(truncated), class = "nanowasm_validation_error")
  expect_error(wasm_validate(truncated), class = "nanowasm_validation_error")
  expect_true(wasm_validate(bytes))
  expect_invisible(wasm_validate(bytes))
})

test_that("bad inputs signal nanowasm_argument_error", {
  expect_error(wasm_module(1:3), class = "nanowasm_argument_error")
  expect_error(wasm_module(c("a", "b")), class = "nanowasm_argument_error")
  expect_error(wasm_module(NA_character_), class = "nanowasm_argument_error")
  expect_error(
    wasm_module(file.path(tempdir(), "no-such-file.wasm")),
    class = "nanowasm_argument_error"
  )
  expect_error(wasm_module(tempdir()), class = "nanowasm_argument_error")
})

test_that("the module size limit is enforced before parsing", {
  withr_opt <- options(nanowasm.max_module_size = 10)
  on.exit(options(withr_opt))
  expect_error(wasm_module(fixture("types")), class = "nanowasm_argument_error")
  expect_error(wasm_module(raw(11)), "limit of 10 bytes")
})

test_that("exports are listed by name with kinds and types", {
  ex <- wasm_exports(wasm_module(fixture("types")))
  expect_identical(names(ex), c("name", "kind", "type"))
  expect_identical(ex$name, sort(ex$name, method = "radix"))
  row <- function(name) unlist(ex[ex$name == name, c("kind", "type")], use.names = FALSE)
  expect_identical(row("add"), c("function", "(i32, i32) -> i32"))
  expect_identical(row("swap"), c("function", "(i32, i64) -> (i64, i32)"))
  expect_identical(row("nothing"), c("function", "() -> ()"))
  expect_identical(row("memory"), c("memory", "min 1 max 2"))
  expect_identical(row("table"), c("table", "funcref min 2"))
  expect_identical(row("counter"), c("global", "mut i32"))
  expect_identical(row("answer"), c("global", "i64"))
})

test_that("imports are listed in module order", {
  mod <- wasm_module(fixture("imports"))
  im <- wasm_imports(mod)
  expect_identical(names(im), c("module", "name", "kind", "type"))
  expect_identical(im$module, c("env", "env", "js", "js"))
  expect_identical(im$name, c("log", "mem", "g", "tbl"))
  expect_identical(im$kind, c("function", "memory", "global", "table"))
  expect_identical(im$type, c("(i32) -> ()", "min 1", "i32", "funcref min 1"))
  expect_identical(nrow(wasm_imports(wasm_module(fixture("types")))), 0L)
})

test_that("exports and imports accept an instance", {
  inst <- fixture_instance("types")
  expect_identical(wasm_exports(inst), wasm_exports(wasm_module(fixture("types"))))
  expect_error(wasm_exports(list()), class = "nanowasm_argument_error")
})

test_that("modules print their exports and imports", {
  expect_snapshot(print(wasm_module(fixture("start"))))
  expect_snapshot(print(wasm_module(fixture("imports"))))
})
