#!/usr/bin/env Rscript
# =============================================================================
# fetch-pmda.R -- Fetch PMDA Validation Rules v6.0 and convert to herald YAML
# =============================================================================
#
# Downloads PMDA Validation Rules from pmda.go.jp, parses the Excel file,
# and writes individual YAML rule files to engines/pmda/.
#
# Usage:
#   Rscript inst/scripts/fetch-pmda.R               # Fetch and parse all
#   Rscript inst/scripts/fetch-pmda.R --dry-run      # Preview without writing
#   Rscript inst/scripts/fetch-pmda.R --force         # Overwrite existing files
#   Rscript inst/scripts/fetch-pmda.R --sheet SDTM    # Single sheet only
#   Rscript inst/scripts/fetch-pmda.R --verbose       # Extra output
#   Rscript inst/scripts/fetch-pmda.R --skip-download # Use cached ZIP
#
# Source:
#   https://www.pmda.go.jp/files/000274354.zip
#   Contains: ValidationRules_20250314.xlsx
#   Sheets: SDTM Rules (511), ADaM Rules (388), Define-XML Rules (161)
#
# Output:
#   engines/pmda/<RULE_ID>.yaml  -- One file per rule (herald flat schema)
#
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

args <- commandArgs(trailingOnly = TRUE)
dry_run  <- "--dry-run" %in% args
force    <- "--force" %in% args
verbose  <- "--verbose" %in% args
skip_dl  <- "--skip-download" %in% args

sheet_filter <- NULL
if ("--sheet" %in% args) {
  idx <- match("--sheet", args)
  if (!is.na(idx) && idx < length(args)) {
    sheet_filter <- args[idx + 1L]
  }
}

# --- Locate repository root ---------------------------------------------------

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) {
  repo_root <- normalizePath(file.path(repo_root, "..", ".."))
}

src_dir  <- file.path(repo_root, ".local", "sources")
out_dir  <- file.path(repo_root, "engines", "pmda")

if (!dir.exists(src_dir)) dir.create(src_dir, recursive = TRUE)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

if (!requireNamespace("readxl", quietly = TRUE)) {
  stop("The readxl package is required: install.packages('readxl')", call. = FALSE)
}
if (!requireNamespace("yaml", quietly = TRUE)) {
  stop("The yaml package is required: install.packages('yaml')", call. = FALSE)
}

cat("=== Herald PMDA Rule Fetch ===\n\n")

# --- Download -----------------------------------------------------------------

PMDA_URL <- "https://www.pmda.go.jp/files/000274354.zip"
zip_path <- file.path(src_dir, "pmda-v6.0.zip")

if (!skip_dl && !file.exists(zip_path)) {
  cat("Downloading PMDA Validation Rules v6.0...\n")
  if (dry_run) {
    cat("  [DRY RUN] Would download from:\n  ", PMDA_URL, "\n\n")
  } else {
    download.file(PMDA_URL, zip_path, mode = "wb", quiet = !verbose)
    cat(sprintf("  Saved: %s (%s bytes)\n\n", zip_path, file.size(zip_path)))
  }
} else {
  cat(sprintf("Using cached: %s\n\n", zip_path))
}

# --- Extract ------------------------------------------------------------------

excel_path <- NULL
if (!dry_run || file.exists(zip_path)) {
  tmp_dir <- tempdir()
  utils::unzip(zip_path, exdir = tmp_dir)
  xlsx_files <- list.files(tmp_dir, pattern = "ValidationRules.*\\.xlsx$",
                           full.names = TRUE)
  if (length(xlsx_files) == 0L) {
    stop("No ValidationRules*.xlsx found in ZIP archive.", call. = FALSE)
  }
  excel_path <- xlsx_files[1L]
  cat(sprintf("Extracted: %s\n\n", basename(excel_path)))
}

# --- Sheet configuration -----------------------------------------------------

SHEETS <- list(
  list(name = "SDTM Rules",      standard = "SDTM",       filter = "SDTM"),
  list(name = "ADaM Rules",      standard = "ADaM",       filter = "ADaM"),
  list(name = "Define-XML Rules", standard = "Define-XML", filter = "Define-XML")
)

if (!is.null(sheet_filter)) {
  SHEETS <- Filter(function(s) {
    grepl(sheet_filter, s$filter, ignore.case = TRUE)
  }, SHEETS)
  if (length(SHEETS) == 0L) {
    stop(sprintf("No sheet matching '%s'. Use: SDTM, ADaM, or Define-XML",
                 sheet_filter), call. = FALSE)
  }
}

# --- Severity mapping ---------------------------------------------------------

map_severity <- function(pmda_cat) {
  pmda_cat <- trimws(tolower(pmda_cat %||% ""))
  switch(pmda_cat,
    "reject"    = "Error",
    "rejection" = "Error",
    "error"     = "Error",
    "warning"   = "Warning",
    "notice"    = "Notice",
    "Error"
  )
}

# --- Category from rule ID prefix ---------------------------------------------

infer_category <- function(rule_id) {
  prefix <- sub("\\d+$", "", rule_id)
  switch(prefix,
    "CT"  = "Controlled Terminology",
    "SD"  = "SDTM Conformance",
    "SDA" = "SDTM Associated Persons",
    "SDC" = "SDTM Custom Domain",
    "AD"  = "ADaM Conformance",
    "ADA" = "ADaM Associated Persons",
    "ADB" = "ADaM BDS",
    "ADC" = "ADaM Custom",
    "DD"  = "Define-XML",
    "DDB" = "Define-XML BDS",
    "OD"  = "ODM/Define-XML",
    "Conformance"
  )
}

# --- Parse a sheet and build rules --------------------------------------------

parse_sheet <- function(excel_path, sheet_cfg) {
  cat(sprintf("Parsing: %s\n", sheet_cfg$name))

  d <- readxl::read_excel(excel_path, sheet = sheet_cfg$name, skip = 1L,
                          col_types = "text")

  # Identify columns by position (consistent across sheets)
  # Col 1: Rule ID, Col 2: Message, Col 3: Description
  # Remaining non-version cols: Domain, PMDA Category

  # Version cols: match pattern like "3.1.2", "1.0", "1.10r1"
  # Last col: PMDA Notes (or similar)

  col_names <- names(d)
  n_cols <- ncol(d)

  # Detect version columns (start with digit)
  ver_idx <- grep("^\\d", col_names)

  # For SDTM: cols 1-5 are ID/MSG/DESC/DOMAIN/CATEGORY, then versions, then notes

  # For Define-XML: cols 1-4 are ID/MSG/DESC/CATEGORY (no DOMAIN), then versions, then notes
  # Detect by checking if col 4 name starts with digit
  has_domain <- if (length(ver_idx) > 0) !4 %in% ver_idx else TRUE

  id_col   <- 1L
  msg_col  <- 2L
  desc_col <- 3L
  if (has_domain) {
    domain_col <- 4L
    sev_col    <- 5L
  } else {
    domain_col <- NA
    sev_col    <- 4L
  }
  notes_col <- n_cols

  # Filter out header row and empty rows
  d <- d[!is.na(d[[id_col]]) & d[[id_col]] != "RULE ID", ]

  cat(sprintf("  Found %d rules\n", nrow(d)))

  rules <- vector("list", nrow(d))

  for (i in seq_len(nrow(d))) {
    row <- d[i, ]

    rule_id     <- trimws(as.character(row[[id_col]]))
    message     <- trimws(as.character(row[[msg_col]] %||% ""))
    description <- trimws(as.character(row[[desc_col]] %||% ""))
    domain_val  <- if (!is.na(domain_col)) trimws(as.character(row[[domain_col]] %||% "")) else ""
    sev_raw     <- trimws(as.character(row[[sev_col]] %||% ""))
    notes_val   <- trimws(as.character(row[[notes_col]] %||% ""))

    # Clean NA strings
    if (identical(message, "NA")) message <- ""
    if (identical(description, "NA")) description <- ""
    if (identical(domain_val, "NA")) domain_val <- ""
    if (identical(sev_raw, "NA")) sev_raw <- ""
    if (identical(notes_val, "NA")) notes_val <- ""

    # Parse domains
    domains <- if (nzchar(domain_val) && !grepl("^ALL$|^GLOBAL", domain_val, ignore.case = TRUE)) {
      strsplit(gsub("\\s+", "", domain_val), ",")[[1]]
    } else {
      list()
    }

    # Collect applicable IG versions
    ig_versions <- c()
    for (vi in ver_idx) {
      cell <- as.character(row[[vi]])
      if (!is.na(cell) && cell == "X") {
        ig_versions <- c(ig_versions, col_names[vi])
      }
    }

    rule <- list(
      id             = rule_id,
      version        = 1L,
      status         = "Reference",
      standard       = sheet_cfg$standard,
      category       = infer_category(rule_id),
      sensitivity    = "Record",
      executability  = "Not Executable",
      description    = description,
      scope          = list(classes = list(), domains = domains),
      check          = list(),
      outcome        = list(
        message  = message,
        severity = map_severity(sev_raw)
      ),
      provenance     = list(
        source_doc    = "PMDA Validation Rules v6.0",
        authority     = "PMDA",
        rule_id       = rule_id,
        pmda_category = sev_raw,
        ig_versions   = as.list(ig_versions)
      )
    )

    # Add notes if present (may be Japanese)
    if (nzchar(notes_val)) {
      rule$provenance$pmda_notes <- notes_val
    }

    rules[[i]] <- rule

    if (verbose) {
      cat(sprintf("    %s: %s\n", rule_id, substr(message, 1, 60)))
    }
  }

  rules
}

# --- Write YAML files ---------------------------------------------------------

write_rules <- function(rules, out_dir, dry_run) {
  written  <- 0L
  skipped  <- 0L

  for (rule in rules) {
    fname <- sprintf("%s.yaml", rule$id)
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

  list(written = written, skipped = skipped)
}

# --- Main loop ----------------------------------------------------------------

total_written <- 0L
total_skipped <- 0L

for (sheet_cfg in SHEETS) {
  rules <- parse_sheet(excel_path, sheet_cfg)
  result <- write_rules(rules, out_dir, dry_run)
  total_written <- total_written + result$written
  total_skipped <- total_skipped + result$skipped
  cat(sprintf("  Written: %d | Skipped (exists): %d\n\n",
              result$written, result$skipped))
}

cat(sprintf("=== Summary ===\n"))
cat(sprintf("  Total written: %d\n", total_written))
cat(sprintf("  Total skipped: %d\n", total_skipped))
cat(sprintf("  Output: %s\n", out_dir))

if (dry_run) {
  cat("\n  [DRY RUN] No files were actually written.\n")
}

cat("\nDone.\n")
