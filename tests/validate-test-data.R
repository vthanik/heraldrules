#!/usr/bin/env Rscript
# =============================================================================
# validate-test-data.R -- Validate embedded tests: blocks in HRL-* YAML rules
# =============================================================================
#
# Checks:
#   1. Every executable HRL-* rule has at least 1 positive and 1 negative test
#   2. Every test case has required fields: name, type, datasets, expected_findings
#   3. type is "positive" or "negative"
#   4. expected_findings is a non-negative integer
#   5. Each dataset in the test has 'variables' (character vector) and
#      'records' (list of rows)
#   6. Record row length matches variables length
#   7. No duplicate test names within a rule
#
# Usage:
#   Rscript tests/validate-test-data.R
#
# Exit codes: 0 = pass, 1 = failures found
#
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

repo_root <- getwd()
if (grepl("tests$", repo_root)) repo_root <- normalizePath(file.path(repo_root, ".."))

if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml required")

cat("=== HRL Rule Test Data Validation ===\n\n")

errors   <- 0L
warnings <- 0L
pass_count <- 0L

fail <- function(msg) { errors   <<- errors   + 1L; cat(sprintf("  FAIL: %s\n", msg)) }
warn <- function(msg) { warnings <<- warnings + 1L; cat(sprintf("  WARN: %s\n", msg)) }
pass <- function(msg) { pass_count <<- pass_count + 1L; cat(sprintf("  PASS: %s\n", msg)) }

# ---------------------------------------------------------------------------
# Load HRL-* YAML files
# ---------------------------------------------------------------------------
herald_dir <- file.path(repo_root, "engines", "herald")
yaml_files <- list.files(herald_dir, pattern = "^HRL-.*\\.yaml$",
                         full.names = TRUE, recursive = FALSE)

executable_execs <- c("Executable", "Fully Executable", "Partially Executable")

rules <- list()
for (f in yaml_files) {
  tryCatch({
    r <- yaml::read_yaml(f)
    rules[[basename(f)]] <- r
  }, error = function(e) {
    fail(sprintf("YAML parse error in %s: %s", basename(f), conditionMessage(e)))
  })
}

cat(sprintf("Loaded %d HRL-* rules\n\n", length(rules)))

# ---------------------------------------------------------------------------
# [1] Executable rules must have tests
# ---------------------------------------------------------------------------
cat("[1] Checking every executable rule has tests...\n")
missing_tests <- 0L

for (fname in names(rules)) {
  r  <- rules[[fname]]
  ex <- r[["executability"]] %||% ""
  if (!ex %in% executable_execs) next

  tests <- r[["tests"]]
  if (is.null(tests) || length(tests) == 0L) {
    warn(sprintf("%s (%s): no tests: block", fname, ex))
    missing_tests <- missing_tests + 1L
    next
  }

  types <- vapply(tests, function(t) t[["type"]] %||% "", character(1L))
  if (!"positive" %in% types) {
    fail(sprintf("%s: no positive test case", fname))
  }
  if (!"negative" %in% types) {
    fail(sprintf("%s: no negative test case", fname))
  }
}

if (missing_tests == 0L && errors == 0L) {
  pass("All executable rules have tests: blocks with positive and negative cases")
} else if (missing_tests > 0L) {
  warn(sprintf("%d executable rules missing tests: blocks", missing_tests))
}

# ---------------------------------------------------------------------------
# [2-7] Validate test case structure
# ---------------------------------------------------------------------------
cat("\n[2] Validating test case structure...\n")
struct_errors <- 0L

for (fname in names(rules)) {
  r     <- rules[[fname]]
  tests <- r[["tests"]]
  if (is.null(tests) || length(tests) == 0L) next

  test_names <- character()

  for (i in seq_along(tests)) {
    tc  <- tests[[i]]
    pfx <- sprintf("%s test[%d]", fname, i)

    # Required fields
    for (fld in c("name", "type", "datasets", "expected_findings")) {
      if (is.null(tc[[fld]])) {
        fail(sprintf("%s: missing field '%s'", pfx, fld))
        struct_errors <- struct_errors + 1L
      }
    }

    # type enum
    typ <- tc[["type"]] %||% ""
    if (nzchar(typ) && !typ %in% c("positive", "negative")) {
      fail(sprintf("%s: type must be 'positive' or 'negative', got '%s'", pfx, typ))
      struct_errors <- struct_errors + 1L
    }

    # expected_findings non-negative integer
    ef <- tc[["expected_findings"]]
    if (!is.null(ef)) {
      if (!is.numeric(ef) || ef < 0L || ef != floor(ef)) {
        fail(sprintf("%s: expected_findings must be a non-negative integer, got '%s'",
                     pfx, ef))
        struct_errors <- struct_errors + 1L
      }
    }

    # duplicate test names
    nm <- tc[["name"]] %||% ""
    if (nzchar(nm)) {
      if (nm %in% test_names) {
        fail(sprintf("%s: duplicate test name '%s'", fname, nm))
        struct_errors <- struct_errors + 1L
      }
      test_names <- c(test_names, nm)
    }

    # datasets structure
    dsets <- tc[["datasets"]]
    if (is.list(dsets)) {
      for (ds_name in names(dsets)) {
        ds  <- dsets[[ds_name]]
        pfx2 <- sprintf("%s dataset[%s]", pfx, ds_name)

        if (is.null(ds[["variables"]])) {
          fail(sprintf("%s: missing 'variables'", pfx2))
          struct_errors <- struct_errors + 1L
          next
        }
        if (is.null(ds[["records"]])) {
          fail(sprintf("%s: missing 'records'", pfx2))
          struct_errors <- struct_errors + 1L
          next
        }

        nvars <- length(ds[["variables"]])
        for (ri in seq_along(ds[["records"]])) {
          row <- ds[["records"]][[ri]]
          if (length(row) != nvars) {
            fail(sprintf("%s record[%d]: %d values but %d variables declared",
                         pfx2, ri, length(row), nvars))
            struct_errors <- struct_errors + 1L
          }
        }
      }
    }
  }
}

if (struct_errors == 0L) {
  pass("All test cases have valid structure")
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
cat(sprintf("\n=== Results ===\n"))
cat(sprintf("  Rules with tests: %d\n",
            sum(vapply(rules, function(r) !is.null(r[["tests"]]), logical(1L)))))
cat(sprintf("  Errors:   %d\n", errors))
cat(sprintf("  Warnings: %d\n", warnings))

if (errors > 0L) {
  cat("\n  VALIDATION FAILED\n")
  quit(status = 1L)
} else {
  cat("\n  ALL CHECKS PASSED\n")
  quit(status = 0L)
}
