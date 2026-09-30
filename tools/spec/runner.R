# Run WebAssembly spec tests (converted by wast2json) against nanowasm.
#
# Usage: Rscript tools/spec/runner.R <json-dir> [known-failures.txt]
#
# Each <name>.json in <json-dir> is one .wast file from the spec test suite.
# The runner drives nanowasm's public R API, so it tests the bundled
# interpreter and the R <-> Wasm value conversions together.
#
# Some commands can't be expressed through the R API and are skipped, not
# failed: values that don't fit a double (i64 beyond 2^53), reference and
# vector types, NaN payloads (R doesn't preserve them), modules that import
# anything but functions, cross-module linking, and text-format assertions.
# A skipped command that may have changed a module's state (a bare action,
# or a call passing a reference) leaves the module in a state later
# assertions don't expect, so the rest of its assertions are skipped too.
# Pure numeric calls with an unpassable value (a large i64, a NaN payload)
# don't.
#
# Failures listed in known-failures.txt (lines of "file:line") are reported
# but don't fail the run; any other failure does, and so does a known
# failure that now passes (so the list stays accurate).

suppressPackageStartupMessages({
  library(nanowasm)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
json_dir <- args[[1]]
known_file <- if (length(args) >= 2) args[[2]] else NA_character_
known <- if (!is.na(known_file) && file.exists(known_file)) {
  x <- trimws(readLines(known_file))
  x[nzchar(x) & !startsWith(x, "#")]
} else {
  character()
}

# ---------------------------------------------------------------- numbers
# Decimal strings of unsigned 64-bit integers, handled exactly.

# a %/% d and a %% d for a decimal string a and a small integer d.
dec_divmod <- function(a, d) {
  digits <- as.integer(strsplit(a, "")[[1]])
  q <- integer(length(digits))
  r <- 0
  for (i in seq_along(digits)) {
    cur <- r * 10 + digits[[i]]
    q[[i]] <- cur %/% d
    r <- cur %% d
  }
  q <- sub("^0+(?=.)", "", paste(q, collapse = ""), perl = TRUE)
  list(q = q, r = r)
}

# The two little-endian 32-bit halves of a uint64 decimal string.
u64_halves <- function(s) {
  dm <- dec_divmod(s, 4294967296)
  c(lo = dm$r, hi = as.numeric(dm$q))
}

u32_to_int <- function(x) as.integer(if (x >= 2^31) x - 2^32 else x)

bits_to_double <- function(s, type) {
  if (type == "f32") {
    readBin(writeBin(u32_to_int(as.numeric(s)), raw(), size = 4), "numeric", size = 4)
  } else {
    h <- u64_halves(s)
    raw8 <- c(
      writeBin(u32_to_int(h[["lo"]]), raw(), size = 4),
      writeBin(u32_to_int(h[["hi"]]), raw(), size = 4)
    )
    readBin(raw8, "numeric", size = 8)
  }
}

# A uint64 decimal string as a signed double, or NULL beyond +-2^53.
i64_value <- function(s) {
  h <- u64_halves(s)
  if (h[["hi"]] < 2^31) {
    v <- h[["hi"]] * 2^32 + h[["lo"]]
    if (v <= 2^53) return(v)
  } else {
    # Negative: -(2^64 - x) = -((2^32 - 1 - hi) * 2^32 + (2^32 - lo)).
    v <- (2^32 - 1 - h[["hi"]]) * 2^32 + (2^32 - h[["lo"]])
    if (v <= 2^53) return(-v)
  }
  NULL
}

is_nan_pattern <- function(v) startsWith(v$value, "nan:")

# The R argument for a spec value, or NULL if it can't be passed.
arg_value <- function(v) {
  switch(v$type,
    i32 = as.numeric(v$value),
    i64 = i64_value(v$value),
    f32 = ,
    f64 = if (is_nan_pattern(v)) NULL else {
      x <- bits_to_double(v$value, v$type)
      if (is.nan(x)) NULL else x
    },
    NULL
  )
}

# Whether a result matches the expected spec value: TRUE, FALSE, or NA
# (can't tell through R).
matches <- function(got, v) {
  switch(v$type,
    i32 = {
      g <- as.numeric(got)
      if (is.na(got)) g <- -2^31
      if (g < 0) g <- g + 2^32
      g == as.numeric(v$value)
    },
    i64 = {
      e <- i64_value(v$value)
      if (is.null(e)) NA else identical(as.numeric(got), e)
    },
    f32 = ,
    f64 = {
      if (is_nan_pattern(v)) return(is.nan(got))
      e <- bits_to_double(v$value, v$type)
      if (is.nan(e)) return(if (is.nan(got)) NA else FALSE)
      identical(got, e) || (got == 0 && e == 0 && identical(1 / got, 1 / e))
    },
    NA
  )
}

# ------------------------------------------------------------------ spectest
# The functions of the spec's "spectest" host module. Its globals, table and
# memory can't be imported through nanowasm, so modules using them are
# skipped.
spectest <- list(spectest = list(
  print = wasm_func(function() NULL),
  print_i32 = wasm_func(function(x) NULL, "i32"),
  print_i64 = wasm_func(function(x) NULL, "i64"),
  print_f32 = wasm_func(function(x) NULL, "f32"),
  print_f64 = wasm_func(function(x) NULL, "f64"),
  print_i32_f32 = wasm_func(function(x, y) NULL, c("i32", "f32")),
  print_f64_f64 = wasm_func(function(x, y) NULL, c("f64", "f64"))
))

limits <- wasm_limits(timeout = 30, frames = 10000, memory = 1024 * 2^20)

# --------------------------------------------------------------------- run
run_file <- function(path) {
  dir <- dirname(path)
  cmds <- fromJSON(path, simplifyVector = FALSE)$commands
  res <- list(pass = 0L, fail = 0L, skip = 0L, failures = character())
  name <- sub("\\.json$", "", basename(path))
  current <- NULL
  named <- list()
  tainted <- character() # names of instances with a skipped action; "" = current
  outcome <- function(ok, cmd, why = "") {
    key <- paste0(name, ":", cmd$line)
    if (is.na(ok)) {
      res$skip <<- res$skip + 1L
    } else if (ok) {
      res$pass <<- res$pass + 1L
    } else {
      res$fail <<- res$fail + 1L
      res$failures <<- c(res$failures, paste0(key, " ", cmd$type, " ", why))
    }
  }
  load <- function(cmd) {
    wasm_instantiate(wasm_module(file.path(dir, cmd$filename)), imports = spectest, limits = limits)
  }
  target <- function(action) {
    if (!is.null(action$module)) named[[action$module]] else current
  }
  skip <- structure(list(), class = "spec_skip")
  perform <- function(action, stateful = FALSE) {
    inst <- target(action)
    key <- if (is.null(action$module)) "" else action$module
    if (is.null(inst) || key %in% tainted) return(skip)
    if (action$type == "get") return(list(wasm_global(inst, action$field)))
    args <- lapply(action$args, arg_value)
    unpassable <- vapply(args, is.null, TRUE)
    if (any(unpassable)) {
      types <- vapply(action$args, `[[`, "", "type")
      if (stateful || any(!types[unpassable] %in% c("i32", "i64", "f32", "f64"))) {
        tainted <<- c(tainted, key)
      }
      return(skip)
    }
    out <- do.call(wasm_call, c(list(inst, action$field), args))
    if (is.list(out)) out else if (is.null(out)) list() else list(out)
  }

  for (cmd in cmds) {
    switch(cmd$type,
      module = {
        current <- tryCatch(load(cmd), error = function(e) NULL)
        tainted <- setdiff(tainted, c("", cmd$name))
        if (!is.null(cmd$name)) named[[cmd$name]] <- current
      },
      register = NULL,
      action = tryCatch(perform(cmd$action, stateful = TRUE), error = function(e) NULL),
      assert_return = {
        if (any(vapply(cmd$expected, function(v) !v$type %in% c("i32", "i64", "f32", "f64"), TRUE))) {
          outcome(NA, cmd)
        } else {
          got <- tryCatch(perform(cmd$action), error = identity)
          if (inherits(got, "spec_skip") || inherits(got, "nanowasm_precision_error") ||
            inherits(got, "nanowasm_unsupported")) {
            outcome(NA, cmd)
          } else if (inherits(got, "error")) {
            outcome(FALSE, cmd, conditionMessage(got))
          } else {
            m <- vapply(seq_along(cmd$expected), function(i) matches(got[[i]], cmd$expected[[i]]), NA)
            outcome(if (any(!m, na.rm = TRUE)) FALSE else if (anyNA(m)) NA else TRUE, cmd,
                    paste(format(unlist(got)), collapse = ", "))
          }
        }
      },
      assert_trap = ,
      assert_exhaustion = {
        cls <- if (cmd$type == "assert_trap") "nanowasm_trap" else "nanowasm_stack_exhausted"
        if (!is.null(cmd$action)) {
          got <- tryCatch(perform(cmd$action), error = identity)
          if (inherits(got, "spec_skip") || inherits(got, "nanowasm_unsupported")) {
            outcome(NA, cmd)
          } else {
            outcome(inherits(got, cls), cmd, if (inherits(got, "error")) conditionMessage(got) else "no trap")
          }
        } else {
          got <- tryCatch(load(cmd), error = identity)
          if (inherits(got, "nanowasm_link_error")) outcome(NA, cmd)
          else outcome(inherits(got, cls), cmd, "instantiation did not trap")
        }
      },
      assert_invalid = ,
      assert_malformed = {
        if (identical(cmd$module_type, "binary")) {
          got <- tryCatch(wasm_module(file.path(dir, cmd$filename)), error = identity)
          outcome(inherits(got, "nanowasm_validation_error"), cmd, "module was accepted")
        } else {
          outcome(NA, cmd)
        }
      },
      assert_unlinkable = ,
      assert_uninstantiable = {
        got <- tryCatch(load(cmd), error = identity)
        outcome(if (inherits(got, "nanowasm_link_error")) NA else inherits(got, "nanowasm_error"),
                cmd, "module instantiated")
      },
      outcome(NA, cmd)
    )
  }
  res
}

files <- sort(list.files(json_dir, pattern = "\\.json$", full.names = TRUE))
results <- lapply(files, run_file)
names(results) <- sub("\\.json$", "", basename(files))

failures <- unlist(lapply(results, `[[`, "failures"), use.names = FALSE)
keys <- sub(" .*", "", failures)
new_failures <- failures[!keys %in% known]
fixed <- setdiff(known, keys)

summary <- data.frame(
  file = names(results),
  passed = vapply(results, `[[`, 1L, "pass"),
  failed = vapply(results, `[[`, 1L, "fail"),
  skipped = vapply(results, `[[`, 1L, "skip"),
  row.names = NULL
)
totals <- colSums(summary[-1])
rate <- totals[["passed"]] / (totals[["passed"]] + totals[["failed"]])

print(summary, row.names = FALSE)
cat(sprintf(
  "\nTotal: %d passed, %d failed (%d known), %d skipped; pass rate %.2f%% of runnable commands.\n",
  totals[["passed"]], totals[["failed"]], length(failures) - length(new_failures),
  totals[["skipped"]], 100 * rate
))
if (length(new_failures)) {
  cat("\nNew failures:\n", paste0("  ", new_failures, "\n"), sep = "")
}
if (length(fixed)) {
  cat("\nKnown failures that now pass (remove them from the list):\n", paste0("  ", fixed, "\n"), sep = "")
}

summary_file <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summary_file)) {
  cat(
    "## WebAssembly spec tests\n\n",
    sprintf("%d passed, %d failed, %d skipped (pass rate %.2f%%).\n\n",
            totals[["passed"]], totals[["failed"]], totals[["skipped"]], 100 * rate),
    "| file | passed | failed | skipped |\n|---|---:|---:|---:|\n",
    paste0("| ", summary$file, " | ", summary$passed, " | ", summary$failed, " | ", summary$skipped, " |\n"),
    file = summary_file, append = TRUE, sep = ""
  )
}

quit(status = if (length(new_failures) || length(fixed)) 1 else 0)
