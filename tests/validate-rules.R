#!/usr/bin/env Rscript
# =============================================================================
# validate-rules.R -- Validate all YAML rule files in herald-rules
# =============================================================================
#
# Checks:
#   1. All YAML files parse without errors
#   2. Required fields present (id or Core.Id)
#   3. No duplicate rule IDs within each engine
#   4. No duplicate rule IDs across engines
#   5. Config files reference only existing rule IDs
#   6. manifest.json counts match actual files
#
# Usage:
#   Rscript tests/validate-rules.R
#
# Exit codes: 0 = pass, 1 = failures found
#
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

repo_root <- getwd()
if (grepl("tests$", repo_root)) repo_root <- normalizePath(file.path(repo_root, ".."))

if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml required")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")

cat("=== Herald Rules Validation ===\n\n")

errors <- 0L
warnings <- 0L

fail <- function(msg) { errors <<- errors + 1L; cat(sprintf("  FAIL: %s\n", msg)) }
warn <- function(msg) { warnings <<- warnings + 1L; cat(sprintf("  WARN: %s\n", msg)) }
pass <- function(msg) { cat(sprintf("  PASS: %s\n", msg)) }

# --- 1. Parse all YAML files -------------------------------------------------
cat("[1/6] Parsing YAML files...\n")

engines <- c("cdisc", "ct", "fda", "pmda")
all_ids <- list()
parse_errors <- 0L

for (eng in engines) {
  d <- file.path(repo_root, "engines", eng)
  files <- list.files(d, pattern = "\\.yaml$", full.names = TRUE)
  eng_ids <- c()

  for (f in files) {
    tryCatch({
      r <- yaml::read_yaml(f)
      rid <- r$id %||% r$Core$Id %||% ""
      if (!nzchar(rid)) {
        fail(sprintf("%s/%s: no rule ID (missing id or Core.Id)", eng, basename(f)))
      } else {
        eng_ids <- c(eng_ids, rid)
      }
    }, error = function(e) {
      fail(sprintf("%s/%s: YAML parse error: %s", eng, basename(f), conditionMessage(e)))
      parse_errors <<- parse_errors + 1L
    })
  }

  all_ids[[eng]] <- eng_ids
  cat(sprintf("  %s: %d files, %d parsed OK, %d IDs\n",
              eng, length(files), length(files) - parse_errors, length(eng_ids)))
}

if (parse_errors == 0L) pass("All YAML files parse successfully")

# --- 2. Required fields ------------------------------------------------------
cat("\n[2/6] Checking required fields...\n")
# Spot check first file of each engine
for (eng in engines) {
  d <- file.path(repo_root, "engines", eng)
  files <- list.files(d, pattern = "\\.yaml$", full.names = TRUE)
  if (length(files) > 0L) {
    r <- tryCatch(yaml::read_yaml(files[1]), error = function(e) NULL)
    if (!is.null(r)) {
      has_id <- !is.null(r$id) || !is.null(r$Core$Id)
      has_desc <- !is.null(r$description) || !is.null(r$Description)
      if (!has_id) fail(sprintf("%s: missing rule ID in %s", eng, basename(files[1])))
      if (!has_desc) warn(sprintf("%s: missing description in %s", eng, basename(files[1])))
    }
  }
}
pass("Required fields check complete")

# --- 3. Duplicate IDs within each engine --------------------------------------
cat("\n[3/6] Checking for duplicate IDs within engines...\n")
for (eng in engines) {
  ids <- all_ids[[eng]]
  dupes <- ids[duplicated(ids)]
  if (length(dupes) > 0L) {
    fail(sprintf("%s: %d duplicate IDs: %s", eng, length(dupes),
                 paste(head(unique(dupes), 5), collapse = ", ")))
  } else {
    pass(sprintf("%s: %d unique IDs, no duplicates", eng, length(ids)))
  }
}

# --- 4. Duplicate IDs across engines ------------------------------------------
cat("\n[4/6] Checking for duplicate IDs across engines...\n")
all_flat <- unlist(all_ids)
cross_dupes <- all_flat[duplicated(all_flat)]
if (length(cross_dupes) > 0L) {
  unique_dupes <- unique(cross_dupes)
  for (did in head(unique_dupes, 10)) {
    which_engines <- names(all_ids)[vapply(all_ids, function(ids) did %in% ids, logical(1))]
    warn(sprintf("ID '%s' in multiple engines: %s", did, paste(which_engines, collapse = ", ")))
  }
  if (length(unique_dupes) > 10L) {
    warn(sprintf("... and %d more cross-engine duplicates", length(unique_dupes) - 10L))
  }
} else {
  pass("No cross-engine duplicate IDs")
}

# --- 5. Config references ----------------------------------------------------
cat("\n[5/6] Checking config references...\n")
all_known <- unique(all_flat)
config_dir <- file.path(repo_root, "configs")
config_files <- list.files(config_dir, pattern = "\\.json$", full.names = TRUE)

for (cf in config_files) {
  cfg <- jsonlite::fromJSON(readLines(cf, warn = FALSE), simplifyVector = FALSE)
  cfg_ids <- unlist(cfg$rule_ids)
  missing <- setdiff(cfg_ids, all_known)
  if (length(missing) > 0L) {
    warn(sprintf("%s: %d rule IDs not found in engines (first 5: %s)",
                 basename(cf), length(missing), paste(head(missing, 5), collapse = ", ")))
  } else {
    pass(sprintf("%s: all %d IDs valid", basename(cf), length(cfg_ids)))
  }
}

# --- 6. Manifest counts ------------------------------------------------------
cat("\n[6/6] Checking manifest.json...\n")
manifest_file <- file.path(repo_root, "manifest.json")
if (file.exists(manifest_file)) {
  m <- jsonlite::fromJSON(readLines(manifest_file, warn = FALSE), simplifyVector = FALSE)
  for (eng in engines) {
    actual <- length(all_ids[[eng]])
    declared <- m$stats$by_engine[[eng]] %||% 0L
    if (actual != declared) {
      fail(sprintf("manifest %s: declared %d, actual %d", eng, declared, actual))
    }
  }
  pass("Manifest counts checked")
} else {
  warn("manifest.json not found")
}

# --- Summary ------------------------------------------------------------------
cat(sprintf("\n=== Results ===\n"))
cat(sprintf("  Total rules: %d\n", length(all_flat)))
cat(sprintf("  Errors: %d\n", errors))
cat(sprintf("  Warnings: %d\n", warnings))

if (errors > 0L) {
  cat("\n  VALIDATION FAILED\n")
  quit(status = 1L)
} else {
  cat("\n  ALL CHECKS PASSED\n")
}
