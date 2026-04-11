#!/usr/bin/env Rscript
# =============================================================================
# validate-define-rules.R -- Content validation for DD (Define-XML) rules
# =============================================================================
#
# Checks beyond structural YAML validity:
#   1. All DD rules parse and have required herald-format fields
#   2. Rule IDs are sequential DD0001--DD0085 with no gaps
#   3. Each rule has valid category, sensitivity, severity values
#   4. Check section contains valid operators
#   5. Provenance section references a spec section
#   6. Cross-reference rules (DD0040, DD0055, DD0059, DD0062--DD0073) use __exists checks
#   7. No duplicate descriptions
#   8. Master CSV has matching rows for all DD rules
#   9. Config files include all DD rule IDs
#  10. Allowable value lists are complete (standards, data types, origins, etc.)
#
# Usage:
#   Rscript tests/validate-define-rules.R
#
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

repo_root <- getwd()
if (grepl("tests$", repo_root)) repo_root <- normalizePath(file.path(repo_root, ".."))

if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml required")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")

cat("=== Define-XML Rule Validation ===\n\n")

errors <- 0L
warnings <- 0L
pass_count <- 0L

fail <- function(msg) { errors <<- errors + 1L; cat(sprintf("  FAIL: %s\n", msg)) }
warn <- function(msg) { warnings <<- warnings + 1L; cat(sprintf("  WARN: %s\n", msg)) }
pass <- function(msg) { pass_count <<- pass_count + 1L; cat(sprintf("  PASS: %s\n", msg)) }

# --- Load all DD rules -------------------------------------------------------
dd_dir <- file.path(repo_root, "engines", "herald", "define")
dd_files <- list.files(dd_dir, pattern = "^DD\\d+\\.yaml$", full.names = TRUE)
cat(sprintf("Found %d DD rule files\n\n", length(dd_files)))

rules <- list()
for (f in dd_files) {
  tryCatch({
    r <- yaml::read_yaml(f)
    rules[[r$id]] <- r
  }, error = function(e) {
    fail(sprintf("%s: YAML parse error: %s", basename(f), conditionMessage(e)))
  })
}

# --- 1. Required herald-format fields ----------------------------------------
cat("[1/10] Required fields...\n")
required <- c("id", "version", "status", "standard", "category",
              "sensitivity", "executability", "description", "check", "outcome")

for (rid in names(rules)) {
  r <- rules[[rid]]
  missing <- setdiff(required, names(r))
  if (length(missing) > 0L) {
    fail(sprintf("%s: missing fields: %s", rid, paste(missing, collapse = ", ")))
  }
}
if (errors == 0L) pass(sprintf("All %d rules have required fields", length(rules)))

# --- 2. Sequential IDs -------------------------------------------------------
cat("\n[2/10] ID sequence...\n")
actual_ids   <- sort(names(rules))
max_num      <- max(as.integer(sub("^DD0*", "", actual_ids)), na.rm = TRUE)
expected_ids <- sprintf("DD%04d", seq_len(max_num))
missing_ids  <- setdiff(expected_ids, actual_ids)

if (length(missing_ids) > 0L) {
  fail(sprintf("Missing IDs (gaps in sequence): %s",
               paste(head(missing_ids, 5), collapse = ", ")))
}
if (length(missing_ids) == 0L) {
  pass(sprintf("DD0001--DD%04d all present, no gaps", max_num))
}

# --- 3. Valid enumerated values -----------------------------------------------
cat("\n[3/10] Enumerated value checks...\n")
valid_categories <- c(
  "Study Metadata", "Dataset Definition", "Standards Reference",
  "Variable Definition", "Origin Metadata", "Cross-Reference",
  "Value-Level Metadata", "Codelist Definition", "Method Definition",
  "Comment Definition", "Orphan Detection", "ARM Metadata",
  "Conformance"
)
valid_sensitivity <- c("Study", "Dataset", "Record")
valid_severity <- c("Error", "Warning")
valid_status <- c("Published", "Reference", "Draft", "Deprecated")

for (rid in names(rules)) {
  r <- rules[[rid]]
  if (!r$category %in% valid_categories) {
    fail(sprintf("%s: invalid category '%s'", rid, r$category))
  }
  if (!r$sensitivity %in% valid_sensitivity) {
    fail(sprintf("%s: invalid sensitivity '%s'", rid, r$sensitivity))
  }
  sev <- r$outcome$severity %||% ""
  if (!sev %in% valid_severity) {
    fail(sprintf("%s: invalid severity '%s'", rid, sev))
  }
  if (!r$status %in% valid_status) {
    fail(sprintf("%s: invalid status '%s'", rid, r$status))
  }
}
pass("Category, sensitivity, severity, status values valid")

# --- 4. Check operators -------------------------------------------------------
cat("\n[4/10] Check operator validation...\n")
# Load allowed operators from shared file
ops_file <- file.path(repo_root, "tests", "allowed-operators.txt")
if (!file.exists(ops_file)) stop("tests/allowed-operators.txt not found")
valid_operators <- grep("^[^#]", readLines(ops_file, warn = FALSE), value = TRUE)
valid_operators <- trimws(valid_operators[nzchar(trimws(valid_operators))])

extract_operators <- function(check) {
  ops <- c()
  if (is.list(check)) {
    for (nm in names(check)) {
      if (nm %in% c("all", "any", "not")) {
        sub <- check[[nm]]
        # "not" may be a single item or a list
        if (is.list(sub) && !is.null(names(sub))) {
          ops <- c(ops, extract_operators(sub))
        } else if (is.list(sub)) {
          for (item in sub) {
            ops <- c(ops, extract_operators(item))
          }
        }
      }
    }
    if ("operator" %in% names(check)) {
      ops <- c(ops, check$operator)
    }
  }
  ops
}

op_errors <- 0L
for (rid in names(rules)) {
  r <- rules[[rid]]
  ops <- extract_operators(r$check)
  bad <- setdiff(ops, valid_operators)
  if (length(bad) > 0L) {
    fail(sprintf("%s: unknown operator(s): %s", rid, paste(bad, collapse = ", ")))
    op_errors <- op_errors + 1L
  }
}
if (op_errors == 0L) pass("All check operators are valid")

# --- 5. Provenance section ----------------------------------------------------
cat("\n[5/10] Provenance references...\n")
prov_errors <- 0L
for (rid in names(rules)) {
  r <- rules[[rid]]
  prov <- r$provenance
  if (is.null(prov)) {
    fail(sprintf("%s: missing provenance section", rid))
    prov_errors <- prov_errors + 1L
  } else {
    if (is.null(prov$section) || !nzchar(prov$section %||% "")) {
      warn(sprintf("%s: provenance missing section reference", rid))
    }
    if (is.null(prov$authority) || !nzchar(prov$authority %||% "")) {
      fail(sprintf("%s: provenance missing authority", rid))
      prov_errors <- prov_errors + 1L
    }
  }
}
if (prov_errors == 0L) pass("All rules have provenance with authority")

# --- 6. Cross-reference rules use __exists checks ----------------------------
cat("\n[6/10] Cross-reference pattern...\n")
xref_ids <- sprintf("DD%04d", c(40, 55, 59, 62:73))
for (rid in xref_ids) {
  r <- rules[[rid]]
  if (is.null(r)) next
  check_str <- paste(capture.output(yaml::as.yaml(r$check)), collapse = " ")
  if (!grepl("__", check_str)) {
    warn(sprintf("%s: cross-ref rule but no __ computed field in check", rid))
  }
}
pass("Cross-reference rules checked")

# --- 7. No duplicate descriptions --------------------------------------------
cat("\n[7/10] Unique descriptions...\n")
descs <- vapply(rules, function(r) r$description %||% "", character(1))
descs <- trimws(descs)
dup_descs <- descs[duplicated(descs)]
if (length(dup_descs) > 0L) {
  for (d in unique(dup_descs)) {
    which_ids <- names(descs)[descs == d]
    warn(sprintf("Duplicate description in: %s", paste(which_ids, collapse = ", ")))
  }
} else {
  pass("All descriptions are unique")
}

# --- 8. Master CSV match -----------------------------------------------------
cat("\n[8/10] Master CSV consistency...\n")
csv_path <- file.path(repo_root, "herald-master-rules.csv")
if (file.exists(csv_path)) {
  csv <- read.csv(csv_path, stringsAsFactors = FALSE)
  csv_dd <- csv$rule_id[grepl("^DD0", csv$rule_id)]
  yaml_dd <- names(rules)

  missing_from_csv <- setdiff(yaml_dd, csv_dd)
  if (length(missing_from_csv) > 0L) {
    fail(sprintf("DD rules in YAML but not CSV: %s",
                 paste(head(missing_from_csv, 5), collapse = ", ")))
  } else {
    pass(sprintf("All %d DD rules present in master CSV", length(yaml_dd)))
  }
} else {
  warn("herald-master-rules.csv not found")
}

# --- 9. Config inclusion -----------------------------------------------------
cat("\n[9/10] Config file inclusion...\n")
for (cfg_name in c("fda-define-xml-2.1.json", "pmda-define-xml-2.1.json")) {
  cfg_path <- file.path(repo_root, "configs", cfg_name)
  if (file.exists(cfg_path)) {
    cfg <- jsonlite::fromJSON(readLines(cfg_path, warn = FALSE), simplifyVector = TRUE)
    cfg_dd <- cfg$rule_ids[grepl("^DD0", cfg$rule_ids)]
    missing <- setdiff(names(rules), cfg_dd)
    if (length(missing) > 0L) {
      fail(sprintf("%s: missing DD rules: %s", cfg_name,
                   paste(head(missing, 5), collapse = ", ")))
    } else {
      pass(sprintf("%s: all DD rules included", cfg_name))
    }
  }
}

# --- 10. Allowable value completeness ----------------------------------------
cat("\n[10/10] Allowable value completeness...\n")

# DD0014: SDTMIG versions
r14 <- rules[["DD0014"]]
if (!is.null(r14)) {
  versions <- r14$check$all[[2]]$value
  expected_v <- c("3.1.2", "3.2", "3.3", "3.4")
  if (!all(expected_v %in% versions)) {
    fail(sprintf("DD0014: missing SDTMIG versions: %s",
                 paste(setdiff(expected_v, versions), collapse = ", ")))
  } else {
    pass("DD0014: SDTMIG versions complete (3.1.2, 3.2, 3.3, 3.4)")
  }
}

# DD0023: Data types
r23 <- rules[["DD0023"]]
if (!is.null(r23)) {
  types <- r23$check$all[[2]]$value
  expected_t <- c("text", "integer", "float", "date", "datetime")
  if (!all(expected_t %in% types)) {
    fail("DD0023: missing core data types")
  } else {
    pass(sprintf("DD0023: data types complete (%d types)", length(types)))
  }
}

# DD0031: Origin types
r31 <- rules[["DD0031"]]
if (!is.null(r31)) {
  origins <- r31$check$all[[2]]$value
  expected_o <- c("Collected", "Derived", "Assigned", "Protocol", "Predecessor")
  if (!all(expected_o %in% origins)) {
    fail("DD0031: missing origin types")
  } else {
    pass(sprintf("DD0031: origin types complete (%d types)", length(origins)))
  }
}

# --- Summary ------------------------------------------------------------------
cat(sprintf("\n=== Results ===\n"))
cat(sprintf("  Rules tested: %d\n", length(rules)))
cat(sprintf("  Passed: %d\n", pass_count))
cat(sprintf("  Errors: %d\n", errors))
cat(sprintf("  Warnings: %d\n", warnings))

if (errors > 0L) {
  cat("\n  VALIDATION FAILED\n")
  quit(status = 1L)
} else {
  cat("\n  ALL CHECKS PASSED\n")
}
