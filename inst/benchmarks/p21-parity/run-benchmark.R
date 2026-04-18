#!/usr/bin/env Rscript
# =============================================================================
# run-benchmark.R -- P21-parity regression harness
# =============================================================================
#
# Reads every fixture in fixtures/, runs herald::validate() against it, and
# diffs the findings against expected-findings.csv. Used to prove that
# herald-rules + herald together reproduce the findings Pinnacle 21 Community
# would report on the same data.
#
# Rules with status `blocked` in expected-findings.csv are not run (they wait
# on herald operators documented in ../../HANDOFF_TO_HERALD_2026-04-18.md).
# They are reported as "SKIP: blocked on <operator>" so the gap is visible
# every run, not silent.
#
# Usage (from repo root):
#   Rscript inst/benchmarks/p21-parity/run-benchmark.R
#
# Exit codes: 0 = all runnable expectations met, 1 = at least one mismatch.
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

repo_root <- getwd()
if (grepl("benchmarks/p21-parity$", repo_root)) {
  repo_root <- normalizePath(file.path(repo_root, "..", "..", ".."))
}
bench_dir <- file.path(repo_root, "inst", "benchmarks", "p21-parity")
fixt_dir  <- file.path(bench_dir, "fixtures")
expected_csv <- file.path(bench_dir, "expected-findings.csv")

stopifnot(file.exists(expected_csv))
expected <- read.csv(expected_csv, stringsAsFactors = FALSE)

cat("=== P21-parity benchmark ===\n")
cat(sprintf("Fixtures:   %d\n", length(unique(expected$fixture))))
cat(sprintf("Expectations: %d\n", nrow(expected)))
cat(sprintf("Runnable today: %d  |  Blocked on herald: %d\n\n",
            sum(expected$status == "runnable_today"),
            sum(expected$status == "blocked")))

# Probe herald availability
has_herald <- requireNamespace("herald", quietly = TRUE)
if (!has_herald) {
  cat("NOTE: `herald` R package not installed. Running in diagnostic mode --\n")
  cat("      only expectation counts are reported; no findings are collected.\n\n")
}

results <- list()
mismatches <- 0L
skipped <- 0L

for (i in seq_len(nrow(expected))) {
  e <- expected[i, ]
  tag <- sprintf("[%s] %s/%s", e$fixture, e$domain, e$rule_id)

  if (e$status == "blocked") {
    cat(sprintf("SKIP %s -- blocked on %s\n", tag, e$blocked_on))
    skipped <- skipped + 1L
    next
  }

  fixt_path <- file.path(fixt_dir, paste0(e$fixture, ".csv"))
  if (!file.exists(fixt_path)) {
    cat(sprintf("FAIL %s -- fixture not found: %s\n", tag, fixt_path))
    mismatches <- mismatches + 1L
    next
  }

  if (!has_herald) {
    cat(sprintf("INFO %s -- expected %d findings (herald not installed; skipping execution)\n",
                tag, e$expected_count))
    next
  }

  # Load fixture as a list keyed by domain, call herald::validate()
  df <- read.csv(fixt_path, stringsAsFactors = FALSE)
  datasets <- setNames(list(df), e$domain)
  rule_id <- e$rule_id

  got <- tryCatch({
    res <- herald::validate(datasets, rules = rule_id)
    f <- res$findings %||% res
    sum(f$rule_id == rule_id, na.rm = TRUE)
  }, error = function(err) {
    cat(sprintf("FAIL %s -- herald error: %s\n", tag, conditionMessage(err)))
    NA_integer_
  })

  if (is.na(got)) {
    mismatches <- mismatches + 1L
    next
  }

  if (got == e$expected_count) {
    cat(sprintf("PASS %s -- %d findings (expected %d)\n", tag, got, e$expected_count))
  } else {
    cat(sprintf("FAIL %s -- %d findings (expected %d)\n", tag, got, e$expected_count))
    mismatches <- mismatches + 1L
  }
  results[[i]] <- list(tag = tag, expected = e$expected_count, got = got)
}

cat("\n=== Results ===\n")
cat(sprintf("  Expectations: %d\n", nrow(expected)))
cat(sprintf("  Blocked (skipped): %d\n", skipped))
cat(sprintf("  Mismatches: %d\n", mismatches))
if (mismatches > 0L) {
  cat("\n  BENCHMARK FAILED\n")
  quit(status = 1L)
} else {
  cat("\n  ALL RUNNABLE EXPECTATIONS MET\n")
}
