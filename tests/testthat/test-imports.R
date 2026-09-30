host_module <- function() wasm_module(fixture("host"))

host_imports <- function(env = list(), math = list()) {
  base <- list(
    env = list(
      add = wasm_func(function(a, b) a + b, c("i32", "i32"), "i32"),
      pair = wasm_func(function() list(2^40, 0.5), results = c("i64", "f64")),
      effect = wasm_func(function() NULL)
    ),
    math = list(twice = wasm_func(function(x) 2 * x, "i64", "i64"))
  )
  base$env[names(env)] <- env
  base$math[names(math)] <- math
  base
}

host_instance <- function(...) {
  wasm_instantiate(host_module(), imports = host_imports(...))
}

test_that("wasm_func() validates and prints", {
  f <- wasm_func(function(a, b) a + b, c("i32", "i32"), "i32")
  expect_s3_class(f, "nanowasm_func")
  expect_false(f$has_caller)
  expect_true(wasm_func(function(caller) NULL)$has_caller)
  expect_snapshot(print(f))
  expect_snapshot(print(wasm_func(function() NULL, results = c("i64", "f64"))))
  expect_error(wasm_func(1), class = "nanowasm_argument_error")
  expect_error(wasm_func(identity, "i8"), class = "nanowasm_argument_error")
  expect_error(wasm_func(identity, results = NA_character_), class = "nanowasm_argument_error")
  expect_true(wasm_func(sum, "i32")$fn(1L) == 1L)
})

test_that("modules call R functions with converted values", {
  inst <- host_instance()
  expect_identical(inst$call_add(2L, 3L), 5L)
  expect_identical(inst$call_pair(), list(2^40, 0.5))
  expect_identical(inst$call_twice(21), 42)
  expect_null(inst$call_effect())
  expect_identical(inst$sum_adds(100L), 5050L)
})

test_that("side effects happen, even if the module traps afterwards", {
  n <- 0
  inst <- host_instance(env = list(effect = wasm_func(function() n <<- n + 1)))
  inst$call_effect()
  expect_identical(n, 1)
  expect_error(inst$effect_then_trap(), class = "nanowasm_trap")
  expect_identical(n, 2)
})

test_that("the start function can call imports", {
  inst <- wasm_instantiate(
    wasm_module(fixture("start-host")),
    imports = list(env = list(init = wasm_func(function() 42L, results = "i32")))
  )
  expect_identical(inst$get(), 42L)

  expect_error(
    wasm_instantiate(
      wasm_module(fixture("start-host")),
      imports = list(env = list(init = wasm_func(function() stop("no"), results = "i32")))
    ),
    class = "nanowasm_host_error"
  )
})

test_that("errors in R functions become nanowasm_host_error with the parent", {
  inst <- host_instance(env = list(add = wasm_func(
    function(a, b) stop("boom"), c("i32", "i32"), "i32"
  )))
  err <- expect_error(inst$call_add(1L, 2L), class = "nanowasm_host_error")
  expect_match(conditionMessage(err), "imported as `env.add` failed: boom")
  expect_s3_class(err$parent, "simpleError")
  expect_identical(conditionMessage(err$parent), "boom")
  expect_identical(deparse(conditionCall(err)), "inst$call_add(1L, 2L)")
  expect_identical(inst$call_twice(2), 4)
})

test_that("bad return values are host errors", {
  bad <- function(value, results = "i32") {
    host_instance(env = list(add = wasm_func(function(a, b) value, c("i32", "i32"), results)))
  }
  expect_error(bad("x")$call_add(1L, 2L), "Result 1 of the R function imported as `env.add`")
  expect_error(bad(1:2)$call_add(1L, 2L), class = "nanowasm_host_error")
  expect_error(bad(1.5)$call_add(1L, 2L), "must be a whole number")
  expect_error(bad(NULL)$call_add(1L, 2L), class = "nanowasm_host_error")

  inst <- host_instance(env = list(pair = wasm_func(function() 1, results = c("i64", "f64"))))
  expect_error(inst$call_pair(), "must return a list of 2 values")
  inst <- host_instance(env = list(pair = wasm_func(function() list(2^60, 1), results = c("i64", "f64"))))
  expect_error(inst$call_pair(), class = "nanowasm_host_error")
})

test_that("i64 arguments too large for a double are errors", {
  called <- FALSE
  inst <- host_instance(math = list(twice = wasm_func(function(x) {
    called <<- TRUE
    x
  }, "i64", "i64")))
  expect_identical(inst$call_twice(2^53), 2^53)
  called <- FALSE
  err <- expect_error(inst$twice_big(), class = "nanowasm_precision_error")
  expect_s3_class(err, "nanowasm_host_error")
  expect_match(conditionMessage(err), "1152921504606846976")
  expect_false(called)
})

test_that("results from R are range-checked like arguments", {
  inst <- host_instance(math = list(twice = wasm_func(function(x) 2^54, "i64", "i64")))
  expect_error(inst$call_twice(1), class = "nanowasm_host_error")
})

test_that("linking reports every problem at once", {
  err <- expect_error(
    wasm_instantiate(host_module(), imports = list(env = list(
      add = wasm_func(function(a) a, "i32", "i32")
    ))),
    class = "nanowasm_link_error"
  )
  expect_match(conditionMessage(err), "missing: `env.pair`, `env.effect`, `math.twice`", fixed = TRUE)
  expect_match(conditionMessage(err), "`env.add` has type (i32, i32) -> i32", fixed = TRUE)
  expect_identical(err$missing$name, c("pair", "effect", "twice"))
  expect_identical(err$mismatch$import, "env.add")
  expect_identical(err$mismatch$given, "(i32) -> i32")

  err <- expect_error(wasm_instantiate(host_module()), class = "nanowasm_link_error")
  expect_identical(nrow(err$missing), 4L)
})

test_that("only functions can be imported", {
  err <- expect_error(
    wasm_instantiate(wasm_module(fixture("imports"))),
    "importing memories, globals, tables is not supported"
  )
  expect_identical(err$missing$name, "log")
})

test_that("imports must be wasm_func()s in a named list", {
  expect_error(
    wasm_instantiate(host_module(), imports = list(env = list(add = function(a, b) a + b))),
    "must be created with `wasm_func()`", fixed = TRUE
  )
  expect_error(wasm_instantiate(host_module(), imports = list(1)), class = "nanowasm_argument_error")
  expect_error(wasm_instantiate(host_module(), imports = "env"), class = "nanowasm_argument_error")
  # Extra imports are ignored.
  imports <- host_imports()
  imports$other <- list(x = wasm_func(identity))
  expect_identical(wasm_instantiate(host_module(), imports = imports)$call_add(1L, 1L), 2L)
})

test_that("the caller gives access to the calling instance's memory", {
  seen <- NULL
  kept <- NULL
  inst <- host_instance(env = list(effect = wasm_func(function(caller) {
    seen <<- wasm_read_string(caller$memory(), 0, 2)
    wasm_write(caller$memory(), 100, 7L, "u8")
    kept <<- caller
  })))
  inst$call_effect()
  expect_identical(seen, "hi")
  expect_identical(wasm_read(wasm_memory(inst), 100, 1), 7L)
  expect_error(kept$memory(), "no longer valid")
  expect_identical(format(kept), "<nanowasm_caller> (no longer valid)")
  expect_snapshot(print(kept))
})

test_that("the caller of the example module logs its greeting", {
  mod <- wasm_module(system.file("extdata", "log.wasm", package = "nanowasm"))
  log <- wasm_func(function(ptr, len, caller) {
    message(wasm_read_string(caller$memory(), ptr, len))
  }, c("i32", "i32"))
  inst <- wasm_instantiate(mod, imports = list(env = list(log = log)))
  expect_message(inst$greet(), "Hello from WebAssembly!")
})

test_that("an import can't call back into its own instance", {
  inst <- NULL
  inst <- host_instance(env = list(effect = wasm_func(function() inst$call_add(1L, 1L))))
  err <- expect_error(inst$call_effect(), class = "nanowasm_host_error")
  expect_s3_class(err$parent, "nanowasm_reentry_error")
  expect_identical(inst$call_add(1L, 1L), 2L)
})

test_that("an import can call another instance", {
  other <- fixture_instance("types")
  inst <- host_instance(env = list(add = wasm_func(
    function(a, b) other$add(a, b) * 10L, c("i32", "i32"), "i32"
  )))
  expect_identical(inst$call_add(2L, 3L), 50L)
})

test_that("non-local exits unwind through WebAssembly and leave it usable", {
  inst <- host_instance(env = list(effect = wasm_func(function() invokeRestart("skip"))))
  expect_identical(withRestarts(inst$call_effect(), skip = function() "skipped"), "skipped")
  expect_identical(inst$call_add(5L, 6L), 11L)

  inst <- host_instance(env = list(effect = wasm_func(function() warning("careful"))))
  expect_identical(
    tryCatch(inst$call_effect(), warning = function(w) conditionMessage(w)),
    "careful"
  )
  expect_identical(inst$call_add(5L, 6L), 11L)
  expect_warning(inst$call_effect(), "careful")

  inst <- host_instance(env = list(effect = wasm_func(function() signalCondition(
    structure(class = c("custom", "condition"), list(message = "x", call = NULL))
  ))))
  expect_identical(tryCatch(inst$call_effect(), custom = function(c) "caught"), "caught")
  expect_identical(inst$sum_adds(10L), 55L)
})

test_that("Ctrl-C inside an import interrupts the call", {
  skip_on_cran()
  skip_on_os("windows")
  inst <- host_instance(env = list(effect = wasm_func(function() Sys.sleep(10))))
  system2("sh", c("-c", shQuote(sprintf("sleep 0.5; kill -INT %d", Sys.getpid()))), wait = FALSE)
  elapsed <- system.time(
    res <- tryCatch(inst$call_effect(), interrupt = function(cnd) cnd)
  )[["elapsed"]]
  expect_s3_class(res, "interrupt")
  expect_lt(elapsed, 9)
  expect_identical(inst$call_add(1L, 2L), 3L)
})

test_that("garbage collection inside an import is safe", {
  inst <- host_instance(env = list(add = wasm_func(function(a, b) {
    gc()
    a + b
  }, c("i32", "i32"), "i32")))
  expect_identical(inst$sum_adds(20L), 210L)

  skip_on_cran()
  inst <- host_instance()
  gctorture(TRUE)
  on.exit(gctorture(FALSE))
  res <- inst$sum_adds(3L)
  gctorture(FALSE)
  expect_identical(res, 6L)
})

test_that("an instance with imports outlives the variables that built it", {
  inst <- local({
    add <- wasm_func(function(a, b) a - b, c("i32", "i32"), "i32")
    host_instance(env = list(add = add))
  })
  gc()
  expect_identical(inst$call_add(5L, 3L), 2L)
})
