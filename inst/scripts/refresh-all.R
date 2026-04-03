#!/usr/bin/env Rscript
# =============================================================================
# refresh-all.R -- Quarterly refresh of all herald-rules sources
# =============================================================================
#
# Single entry point to re-fetch, regenerate, and validate all rules.
# Run this every quarter when new CT packages or regulatory updates drop.
#
# Usage:
#   Rscript inst/scripts/refresh-all.R              # Full refresh
#   Rscript inst/scripts/refresh-all.R --dry-run     # Preview only
#   Rscript inst/scripts/refresh-all.R --skip-fetch   # Rebuild without fetching
#   Rscript inst/scripts/refresh-all.R --verbose      # Extra output
#
# Prerequisites:
#   - CDISC Library API key in .local/.env (CDISC_API_KEY=...)
#   - FDA Validator Rules v1.6 Excel in .local/sources/
#   - Internet access for PMDA and NCI EVS downloads
#
# Steps:
#   1. Fetch CDISC conformance rules (SDTMIG 3.2, 3.3)
#   2. Fetch PMDA Validation Rules v6.0
#   3. Parse FDA Validator Rules v1.6
#   4. Fetch controlled terminology (CDISC Library + NCI EVS extensibility)
#   5. Generate per-codelist CT rules
#   6. Rebuild configs
#   7. Rebuild master CSV
#   8. Regenerate manifest.json
#   9. Validate all rules
#
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
dry_run    <- "--dry-run" %in% args
skip_fetch <- "--skip-fetch" %in% args
verbose    <- "--verbose" %in% args

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) {
  repo_root <- normalizePath(file.path(repo_root, "..", ".."))
}

scripts_dir <- file.path(repo_root, "inst", "scripts")

run_script <- function(name, extra_args = character(0)) {
  script <- file.path(scripts_dir, name)
  if (!file.exists(script)) {
    cat(sprintf("  SKIP: %s not found\n", name))
    return(invisible(1L))
  }
  all_args <- c(extra_args, if (verbose) "--verbose")
  cmd <- paste("Rscript", shQuote(script), paste(all_args, collapse = " "))
  cat(sprintf("\n{'='*60}\n"))
  cat(sprintf("  Running: %s %s\n", name, paste(extra_args, collapse = " ")))
  cat(sprintf("{'='*60}\n\n"))
  rc <- system(cmd)
  if (rc != 0L) cat(sprintf("  WARNING: %s exited with code %d\n", name, rc))
  invisible(rc)
}

cat("=== Herald Rules Quarterly Refresh ===\n")
cat(sprintf("  Repo: %s\n", repo_root))
cat(sprintf("  Date: %s\n", Sys.Date()))
cat(sprintf("  Mode: %s\n\n", if (dry_run) "DRY RUN" else if (skip_fetch) "REBUILD ONLY" else "FULL REFRESH"))

start_time <- Sys.time()

# --- Step 1: Fetch CDISC conformance rules ------------------------------------
if (!skip_fetch) {
  cat("\n[1/9] Fetching CDISC conformance rules from Library API...\n")
  run_script("fetch-cdisc.R", c("--force", if (dry_run) "--dry-run"))
}

# --- Step 2: Fetch PMDA validation rules --------------------------------------
if (!skip_fetch) {
  cat("\n[2/9] Fetching PMDA Validation Rules v6.0...\n")
  run_script("fetch-pmda.R", c("--force", if (dry_run) "--dry-run"))
}

# --- Step 3: Parse FDA validator rules ----------------------------------------
if (!skip_fetch) {
  cat("\n[3/9] Parsing FDA Validator Rules v1.6...\n")
  run_script("fetch-fda.R", c("--force", "--skip-send", if (dry_run) "--dry-run"))
}

# --- Step 4-5: Fetch CT and generate per-codelist rules -----------------------
if (!skip_fetch) {
  cat("\n[4/9] Fetching controlled terminology (CDISC Library + NCI EVS)...\n")
  # CT fetch is done inline since it needs extensibility merge
  source(file.path(scripts_dir, "fetch-ct-full.R"), local = TRUE)
}

# --- Step 6: Rebuild configs --------------------------------------------------
cat("\n[6/9] Rebuilding configs...\n")
if (!dry_run) {
  source(file.path(scripts_dir, "build-configs.R"), local = TRUE)
}

# --- Step 7: Rebuild master CSV -----------------------------------------------
cat("\n[7/9] Rebuilding master CSV...\n")
if (!dry_run) {
  run_script("build-master-csv.R")
}

# --- Step 8: Regenerate manifest ----------------------------------------------
cat("\n[8/9] Regenerating manifest.json...\n")
if (!dry_run) {
  source(file.path(scripts_dir, "build-manifest.R"), local = TRUE)
}

# --- Step 9: Validate ---------------------------------------------------------
cat("\n[9/9] Validating all rules...\n")
test_script <- file.path(repo_root, "tests", "validate-rules.R")
if (file.exists(test_script)) {
  rc <- system(paste("Rscript", shQuote(test_script)))
  if (rc != 0L) {
    cat("\n  VALIDATION FAILED -- check output above\n")
    quit(status = 1L)
  }
} else {
  cat("  SKIP: tests/validate-rules.R not found\n")
}

# --- Summary ------------------------------------------------------------------
elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

cat(sprintf("\n{'='*60}\n"))
cat(sprintf("=== Refresh Complete ===\n"))
cat(sprintf("  Elapsed: %.0f seconds\n", elapsed))

# Count files
for (eng in c("cdisc", "fda", "pmda", "ct")) {
  d <- file.path(repo_root, "engines", eng)
  n <- length(list.files(d, pattern = "\\.yaml$"))
  cat(sprintf("  engines/%s: %d rules\n", eng, n))
}

if (dry_run) cat("\n  [DRY RUN] No files were actually modified.\n")
cat("\nDone.\n")
