#!/usr/bin/env Rscript
# =============================================================================
# fetch-fda.R -- Parse FDA Validator Rules v1.6 Excel to herald YAML
# =============================================================================
#
# The FDA Validator Rules v1.6 (December 2022) Excel must be manually
# downloaded from FDA.gov. This script parses the Excel and writes YAML.
#
# Usage:
#   Rscript inst/scripts/fetch-fda.R                              # Parse
#   Rscript inst/scripts/fetch-fda.R --dry-run                    # Preview
#   Rscript inst/scripts/fetch-fda.R --force                      # Overwrite
#   Rscript inst/scripts/fetch-fda.R --source path/to/file.xlsx   # Explicit path
#   Rscript inst/scripts/fetch-fda.R --skip-send                  # Skip SEND rules
#   Rscript inst/scripts/fetch-fda.R --verbose                    # Extra output
#
# Source file search order:
#   1. --source argument
#   2. .local/sources/fda-validator-rules-v1.6.xlsx
#   3. ~/downloads/FDA Validator Rules v1.6*.xlsx
#
# Output:
#   engines/fda/FDAV-<ID>.yaml  -- One file per rule (CDISC CORE schema)
#
# Note: These are FDAV (Validator) rules, distinct from existing FDAB
#       (Business Rules v1.5) files. Both coexist in engines/fda/.
#
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

args <- commandArgs(trailingOnly = TRUE)
dry_run   <- "--dry-run" %in% args
force     <- "--force" %in% args
verbose   <- "--verbose" %in% args
skip_send <- "--skip-send" %in% args

source_override <- NULL
if ("--source" %in% args) {
  idx <- match("--source", args)
  if (!is.na(idx) && idx < length(args)) {
    source_override <- args[idx + 1L]
  }
}

# --- Locate repository root ---------------------------------------------------

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) {
  repo_root <- normalizePath(file.path(repo_root, "..", ".."))
}

src_dir <- file.path(repo_root, ".local", "sources")
out_dir <- file.path(repo_root, "engines", "fda")

if (!dir.exists(src_dir)) dir.create(src_dir, recursive = TRUE)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

if (!requireNamespace("readxl", quietly = TRUE)) {
  stop("The readxl package is required: install.packages('readxl')", call. = FALSE)
}
if (!requireNamespace("yaml", quietly = TRUE)) {
  stop("The yaml package is required: install.packages('yaml')", call. = FALSE)
}

cat("=== Herald FDA Validator Rules Fetch ===\n\n")

# --- Locate source file -------------------------------------------------------

locate_source <- function() {
  candidates <- c(
    source_override,
    file.path(src_dir, "fda-validator-rules-v1.6.xlsx"),
    Sys.glob(file.path(src_dir, "*FDA*Validator*1.6*.xlsx")),
    Sys.glob(file.path(src_dir, "*fda*validator*.xlsx")),
    Sys.glob("~/downloads/FDA Validator Rules v1.6*.xlsx"),
    Sys.glob("~/Downloads/FDA Validator Rules v1.6*.xlsx")
  )
  candidates <- candidates[!is.na(candidates)]
  for (f in candidates) {
    if (file.exists(f)) return(normalizePath(f))
  }
  NULL
}

excel_path <- locate_source()

if (is.null(excel_path)) {
  cat("FDA Validator Rules v1.6 Excel NOT FOUND.\n\n")
  cat("Please download manually:\n")
  cat("  1. Visit: https://www.fda.gov/industry/study-data-standards-resources/\n")
  cat("           study-data-submission-cder-and-cber\n")
  cat("  2. Download 'FDA Validator Rules v1.6' Excel file\n")
  cat("  3. Place at: .local/sources/fda-validator-rules-v1.6.xlsx\n")
  cat("  4. Re-run this script\n")
  quit(status = 1L)
}

cat(sprintf("Source: %s\n\n", excel_path))

# Copy to .local/sources/ for caching if not already there
cached <- file.path(src_dir, "fda-validator-rules-v1.6.xlsx")
if (!file.exists(cached) && !dry_run) {
  file.copy(excel_path, cached)
  cat(sprintf("Cached to: %s\n\n", cached))
}

# --- Parse Excel --------------------------------------------------------------

cat("Parsing FDA Validator Rules v1.6...\n")

d <- readxl::read_excel(excel_path, sheet = "FDA Validator Rules v1.6",
                        skip = 1L, col_types = "text")

# Standardize column names
raw_names <- names(d)
names(d) <- c("rule_id", "publisher", "publisher_id", "message", "description",
              "domains", paste0("ig_", seq_len(ncol(d) - 6L)))

# Recover IG version names from original headers
ig_names <- raw_names[7:length(raw_names)]
# Clean \r\n from Excel headers
ig_names <- gsub("\\r\\n", " ", ig_names)

cat(sprintf("  Raw rows: %d\n", nrow(d)))
cat(sprintf("  IG versions: %s\n", paste(ig_names, collapse = ", ")))

# Filter empty rows
d <- d[!is.na(d$rule_id) & nzchar(trimws(d$rule_id)), ]
cat(sprintf("  Valid rules: %d\n", nrow(d)))

# --- Skip SEND if requested ---------------------------------------------------

if (skip_send) {
  is_send <- grepl("^SE\\d", d$rule_id)
  cat(sprintf("  Skipping SEND rules: %d\n", sum(is_send)))
  d <- d[!is_send, ]
  cat(sprintf("  Remaining: %d\n", nrow(d)))
}

# --- Determine standard from rule ID and IG flags ----------------------------

determine_standard <- function(rule_id, row, ig_names) {
  prefix <- sub("\\d+$", "", rule_id)
  if (prefix == "SE") return("SEND")
  if (prefix %in% c("SD", "SDA", "SDC", "CT")) return("SDTM")

  # Check IG flags
  ig_cols <- grep("^ig_", names(row))
  for (j in ig_cols) {
    if (!is.na(row[[j]]) && row[[j]] == "X") {
      ig <- ig_names[j - 6L]
      if (grepl("SDTMIG", ig)) return("SDTM")
      if (grepl("SENDIG", ig)) return("SEND")
    }
  }
  "SDTM"
}

# --- Build rules --------------------------------------------------------------

cat("\nBuilding YAML rules...\n")

rules <- vector("list", nrow(d))

for (i in seq_len(nrow(d))) {
  row <- d[i, ]

  rule_id     <- trimws(row$rule_id)
  publisher   <- trimws(row$publisher %||% "")
  pub_id      <- trimws(row$publisher_id %||% "")
  message     <- trimws(row$message %||% "")
  description <- trimws(row$description %||% "")
  domains_raw <- trimws(row$domains %||% "")

  # Clean NA strings
  if (identical(publisher, "NA")) publisher <- ""
  if (identical(pub_id, "NA")) pub_id <- ""
  if (identical(message, "NA")) message <- ""
  if (identical(description, "NA")) description <- ""
  if (identical(domains_raw, "NA")) domains_raw <- ""

  # Standard
  standard <- determine_standard(rule_id, row, ig_names)

  # Domains
  domains_str <- if (nzchar(domains_raw) && !grepl("^ALL$", domains_raw, ignore.case = TRUE)) {
    domains_raw
  } else {
    ""
  }

  # Collect applicable IG versions
  ig_cols <- grep("^ig_", names(row))
  ig_applicable <- c()
  for (j in ig_cols) {
    if (!is.na(row[[j]]) && row[[j]] == "X") {
      ig_applicable <- c(ig_applicable, ig_names[j - 6L])
    }
  }

  # Build CDISC CORE schema (matching existing engines/fda/ format)
  herald_id <- sprintf("FDAV-%s", rule_id)

  rule <- list(
    Core = list(
      Id      = herald_id,
      Status  = "Reference",
      Version = "1"
    ),
    Description    = description,
    Check          = list(),
    Outcome        = list(Message = message),
    `Rule Type`    = "Record Data",
    Sensitivity    = "Record",
    Authorities    = list(
      list(Organization = if (nzchar(publisher)) publisher else "FDA")
    ),
    Source         = "FDA Validator Rules v1.6",
    Domains        = domains_str,
    Standard       = standard,
    `Publisher ID` = pub_id,
    `IG Versions`  = as.list(ig_applicable)
  )

  rules[[i]] <- rule

  if (verbose) {
    cat(sprintf("  %s -> %s: %s\n", rule_id, herald_id, substr(message, 1, 50)))
  }
}

# --- Write YAML files ---------------------------------------------------------

written <- 0L
skipped <- 0L

for (rule in rules) {
  fname <- sprintf("%s.yaml", rule$Core$Id)
  fpath <- file.path(out_dir, fname)

  if (file.exists(fpath) && !force) {
    skipped <- skipped + 1L
    next
  }

  if (dry_run) {
    cat(sprintf("  [DRY RUN] Would write: %s\n", fname))
    written <- written + 1L
    next
  }

  yaml_str <- yaml::as.yaml(rule, indent.mapping.sequence = TRUE)
  writeLines(yaml_str, fpath, useBytes = TRUE)
  written <- written + 1L
}

# --- Summary ------------------------------------------------------------------

cat(sprintf("\n=== Summary ===\n"))
cat(sprintf("  Total parsed:  %d\n", length(rules)))
cat(sprintf("  Written:       %d\n", written))
cat(sprintf("  Skipped:       %d (existing, use --force to overwrite)\n", skipped))
cat(sprintf("  Output:        %s\n", out_dir))

# Breakdown by standard
stds <- vapply(rules, function(r) r$Standard, character(1))
cat(sprintf("\n  By standard:\n"))
for (s in sort(unique(stds))) {
  cat(sprintf("    %s: %d\n", s, sum(stds == s)))
}

if (dry_run) {
  cat("\n  [DRY RUN] No files were actually written.\n")
}

cat("\nDone.\n")
