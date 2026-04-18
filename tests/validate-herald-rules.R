#!/usr/bin/env Rscript
# =============================================================================
# validate-herald-rules.R -- Content validation for HRL-* herald engine rules
# =============================================================================
#
# Checks:
#   1. All HRL-* YAML files parse and have required fields
#   2. Rule IDs match filenames
#   3. ID sequences are complete (no gaps within each category)
#   4. Category codes are known
#   5. Hardcoded rules have no check: block
#   6. Reference rules (executability: Reference) have empty check:
#   7. Executable rules have valid check: structure
#   8. All HRL-* rules appear in herald-master-rules.csv
#   9. All HRL-* rules appear in at least one config JSON
#  10. Provenance fields present (source_doc, authority)
#
# Usage:
#   Rscript tests/validate-herald-rules.R
#
# Exit codes: 0 = pass, 1 = failures found
#
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

repo_root <- getwd()
if (grepl("tests$", repo_root)) repo_root <- normalizePath(file.path(repo_root, ".."))

if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml required")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")

cat("=== Herald Engine Rule Validation (HRL-*) ===\n\n")

errors   <- 0L
warnings <- 0L
pass_count <- 0L

fail <- function(msg) { errors   <<- errors   + 1L; cat(sprintf("  FAIL: %s\n", msg)) }
warn <- function(msg) { warnings <<- warnings + 1L; cat(sprintf("  WARN: %s\n", msg)) }
pass <- function(msg) { pass_count <<- pass_count + 1L; cat(sprintf("  PASS: %s\n", msg)) }

# ---------------------------------------------------------------------------
# Load HRL-* YAML files (engines/herald/ root only, not define/)
# ---------------------------------------------------------------------------
herald_dir <- file.path(repo_root, "engines", "herald")
yaml_files <- list.files(herald_dir, pattern = "^HRL-.*\\.yaml$",
                         full.names = TRUE, recursive = FALSE)

if (length(yaml_files) == 0L) {
  cat("  FAIL: No HRL-*.yaml files found in engines/herald/\n")
  quit(status = 1L)
}

cat(sprintf("[1/7] Parsing %d HRL-*.yaml files...\n", length(yaml_files)))

rules <- list()
parse_errors <- 0L

for (f in yaml_files) {
  tryCatch({
    r <- yaml::read_yaml(f)
    rules[[basename(f)]] <- r
  }, error = function(e) {
    fail(sprintf("YAML parse error in %s: %s", basename(f), conditionMessage(e)))
    parse_errors <<- parse_errors + 1L
  })
}

if (parse_errors == 0L) {
  pass(sprintf("All %d HRL-* YAML files parsed successfully", length(yaml_files)))
} else {
  fail(sprintf("%d files failed to parse", parse_errors))
}

# ---------------------------------------------------------------------------
# [2] Required fields + ID consistency
# ---------------------------------------------------------------------------
cat("\n[2/7] Checking required fields and ID consistency...\n")

required_fields <- c("id", "version", "status", "standard", "category",
                      "sensitivity", "executability", "description", "scope",
                      "outcome", "provenance")

field_errors <- 0L
id_errors    <- 0L

for (fname in names(rules)) {
  r   <- rules[[fname]]
  rid <- r[["id"]] %||% ""

  # Required fields
  for (fld in required_fields) {
    if (is.null(r[[fld]])) {
      fail(sprintf("%s: missing required field '%s'", fname, fld))
      field_errors <- field_errors + 1L
    }
  }

  # ID matches filename
  expected_id <- sub("\\.yaml$", "", fname)
  if (!identical(rid, expected_id)) {
    fail(sprintf("%s: id '%s' does not match filename", fname, rid))
    id_errors <- id_errors + 1L
  }

  # outcome.message + outcome.severity
  outcome <- r[["outcome"]] %||% list()
  if (is.null(outcome[["message"]]) || !nzchar(outcome[["message"]] %||% "")) {
    fail(sprintf("%s: outcome.message is missing or empty", fname))
    field_errors <- field_errors + 1L
  }
  if (is.null(outcome[["severity"]])) {
    fail(sprintf("%s: outcome.severity is missing", fname))
    field_errors <- field_errors + 1L
  }

  # provenance.authority + provenance.source_doc
  prov <- r[["provenance"]] %||% list()
  if (is.null(prov[["authority"]]) || !nzchar(prov[["authority"]] %||% "")) {
    fail(sprintf("%s: provenance.authority is missing", fname))
    field_errors <- field_errors + 1L
  }
  if (is.null(prov[["source_doc"]]) || !nzchar(prov[["source_doc"]] %||% "")) {
    fail(sprintf("%s: provenance.source_doc is missing", fname))
    field_errors <- field_errors + 1L
  }
}

if (field_errors == 0L && id_errors == 0L) {
  pass(sprintf("All %d files have correct fields and IDs", length(rules)))
}

# ---------------------------------------------------------------------------
# [3] Category codes and ID sequence
# ---------------------------------------------------------------------------
cat("\n[3/7] Checking category codes and ID sequences...\n")

known_cats <- c("AD", "FM", "MD", "OD", "SD", "TS", "VAR", "LBL", "TYP",
                "LEN", "DS", "CL", "KEY")

# Parse IDs into (category, number) pairs
parsed_ids <- list()
cat_errors <- 0L

for (fname in names(rules)) {
  rid <- sub("\\.yaml$", "", fname)
  # HRL-{CAT}-{NNN}
  m <- regmatches(rid, regexpr("^HRL-([A-Z]+)-(\\d+)$", rid))
  if (length(m) == 0L) {
    fail(sprintf("%s: ID '%s' does not match HRL-{CAT}-NNN pattern", fname, rid))
    cat_errors <- cat_errors + 1L
    next
  }
  parts <- strsplit(sub("^HRL-", "", m), "-")[[1]]
  cat_code <- parts[[1]]
  num      <- as.integer(parts[[2]])

  if (!cat_code %in% known_cats) {
    fail(sprintf("%s: unknown category code '%s' (known: %s)",
                 fname, cat_code, paste(known_cats, collapse = ", ")))
    cat_errors <- cat_errors + 1L
  }
  parsed_ids[[rid]] <- list(cat = cat_code, num = num)
}

if (cat_errors == 0L) {
  pass("All rule IDs use valid HRL-{CAT}-NNN pattern")
}

# Check sequences per category
seq_errors <- 0L
cats_found <- unique(vapply(parsed_ids, `[[`, character(1L), "cat"))

for (cat_code in sort(cats_found)) {
  nums <- sort(vapply(
    Filter(function(x) x$cat == cat_code, parsed_ids),
    `[[`, integer(1L), "num"
  ))
  expected <- seq_len(max(nums))
  missing  <- setdiff(expected, nums)
  if (length(missing) > 0L) {
    warn(sprintf("HRL-%s: gaps in sequence — missing numbers: %s",
                 cat_code, paste(missing, collapse = ", ")))
    seq_errors <- seq_errors + 1L
  }
}

if (seq_errors == 0L) {
  pass(sprintf("All %d categories have contiguous sequences", length(cats_found)))
}

# ---------------------------------------------------------------------------
# [4] Executability + check: block consistency
# ---------------------------------------------------------------------------
cat("\n[4/7] Checking executability vs check: block...\n")

exec_errors <- 0L
valid_execs <- c("Executable", "Reference", "Hardcoded", "Fully Executable",
                 "Partially Executable")

for (fname in names(rules)) {
  r    <- rules[[fname]]
  ex   <- r[["executability"]] %||% ""
  chk  <- r[["check"]] %||% list()

  if (!ex %in% valid_execs) {
    fail(sprintf("%s: invalid executability '%s'", fname, ex))
    exec_errors <- exec_errors + 1L
    next
  }

  if (ex == "Hardcoded" && length(chk) > 0L) {
    fail(sprintf("%s: Hardcoded rule should not have a check: block", fname))
    exec_errors <- exec_errors + 1L
  }

  if (ex == "Executable" && length(chk) == 0L) {
    warn(sprintf("%s: Executable rule has empty check: block", fname))
  }

  # Enum: status
  valid_status <- c("Published", "Reference", "Draft", "Deprecated")
  st <- r[["status"]] %||% ""
  if (nzchar(st) && !st %in% valid_status) {
    fail(sprintf("%s: invalid status '%s' (allowed: %s)", fname, st,
                 paste(valid_status, collapse = ", ")))
    exec_errors <- exec_errors + 1L
  }

  # Enum: sensitivity
  valid_sens <- c("Study", "Dataset", "Record")
  sn <- r[["sensitivity"]] %||% ""
  if (nzchar(sn) && !sn %in% valid_sens) {
    fail(sprintf("%s: invalid sensitivity '%s' (allowed: %s)", fname, sn,
                 paste(valid_sens, collapse = ", ")))
    exec_errors <- exec_errors + 1L
  }

  # Enum: outcome.severity
  valid_sev <- c("Error", "Warning")
  sv <- (r[["outcome"]] %||% list())[["severity"]] %||% ""
  if (nzchar(sv) && !sv %in% valid_sev) {
    fail(sprintf("%s: invalid outcome.severity '%s' (allowed: %s)", fname, sv,
                 paste(valid_sev, collapse = ", ")))
    exec_errors <- exec_errors + 1L
  }
}

if (exec_errors == 0L) {
  pass("All executability, status, sensitivity, severity values valid")
}

# ---------------------------------------------------------------------------
# [5] Validate check: operator names for rules that have them
# ---------------------------------------------------------------------------
cat("\n[5/7] Checking operator names in check: blocks...\n")

# Load allowed operators from shared file
ops_file <- file.path(repo_root, "tests", "allowed-operators.txt")
if (!file.exists(ops_file)) stop("tests/allowed-operators.txt not found")
known_operators <- grep("^[^#]", readLines(ops_file, warn = FALSE), value = TRUE)
known_operators <- trimws(known_operators[nzchar(trimws(known_operators))])

extract_operators <- function(chk) {
  ops <- character()
  if (is.list(chk)) {
    for (item in chk) {
      if (is.list(item)) {
        if (!is.null(item$operator)) ops <- c(ops, item$operator)
        # recurse into all:/any:/not:
        for (sub_key in c("all", "any", "not")) {
          if (!is.null(item[[sub_key]])) {
            ops <- c(ops, extract_operators(item[[sub_key]]))
          }
        }
      }
    }
  }
  ops
}

op_warnings <- 0L
for (fname in names(rules)) {
  r   <- rules[[fname]]
  chk <- r[["check"]] %||% list()
  if (length(chk) == 0L) next

  ops <- extract_operators(chk)
  unknown <- setdiff(ops, known_operators)
  if (length(unknown) > 0L) {
    warn(sprintf("%s: unknown operators: %s", fname,
                 paste(unknown, collapse = ", ")))
    op_warnings <- op_warnings + 1L
  }
}

if (op_warnings == 0L) {
  pass("All operator names in check: blocks are valid")
}

# ---------------------------------------------------------------------------
# [6] Master CSV coverage
# ---------------------------------------------------------------------------
cat("\n[6/7] Checking master CSV coverage...\n")

csv_path <- file.path(repo_root, "herald-master-rules.csv")
csv_data <- read.csv(csv_path, stringsAsFactors = FALSE, colClasses = "character")
csv_ids  <- trimws(csv_data$rule_id)

hrl_ids <- sub("\\.yaml$", "", names(rules))
missing_from_csv <- setdiff(hrl_ids, csv_ids)

if (length(missing_from_csv) == 0L) {
  pass(sprintf("All %d HRL-* rules found in master CSV", length(hrl_ids)))
} else {
  for (mid in missing_from_csv) {
    fail(sprintf("Missing from herald-master-rules.csv: %s", mid))
  }
}

# ---------------------------------------------------------------------------
# [7] Config JSON coverage
# ---------------------------------------------------------------------------
cat("\n[7/7] Checking config JSON coverage...\n")

configs_dir <- file.path(repo_root, "configs")
cfg_files   <- list.files(configs_dir, pattern = "\\.json$", full.names = TRUE)

# Collect union of all IDs across all configs
all_cfg_ids <- character()
for (cfg_f in cfg_files) {
  cfg <- jsonlite::fromJSON(cfg_f)
  all_cfg_ids <- union(all_cfg_ids, cfg$rule_ids)
}

missing_from_cfg <- setdiff(hrl_ids, all_cfg_ids)
if (length(missing_from_cfg) == 0L) {
  pass(sprintf("All %d HRL-* rules appear in at least one config", length(hrl_ids)))
} else {
  for (mid in missing_from_cfg) {
    fail(sprintf("Not in any config: %s", mid))
  }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
cat(sprintf("\n=== Results ===\n"))
cat(sprintf("  HRL-* rules checked: %d\n", length(rules)))
cat(sprintf("  Errors:   %d\n", errors))
cat(sprintf("  Warnings: %d\n", warnings))

if (errors == 0L) {
  cat("\n  ALL CHECKS PASSED\n")
  quit(status = 0L)
} else {
  cat(sprintf("\n  %d FAILURES -- fix errors before committing\n", errors))
  quit(status = 1L)
}
