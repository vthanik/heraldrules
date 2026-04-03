#!/usr/bin/env Rscript
# =============================================================================
# build-master-csv.R -- Build the herald master rules CSV (source of truth)
# =============================================================================
#
# Combines all rule sources into a single comprehensive CSV file.
# This CSV is the canonical reference for audit, validation, and compliance.
#
# Sources:
#   1. CDISC Library API rules (engines/cdisc/)
#   2. FDA Validator Rules v1.6 (.local/sources/)
#   3. PMDA Validation Rules v6.0 (.local/sources/)
#
# Output:
#   herald-master-rules.csv
#   CHANGELOG.md (appended)
#
# Usage:
#   Rscript inst/scripts/build-master-csv.R
#
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x
na_to_empty <- function(x) { x[is.na(x)] <- ""; x }

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) {
  repo_root <- normalizePath(file.path(repo_root, "..", ".."))
}

if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml required")
if (!requireNamespace("readxl", quietly = TRUE)) stop("readxl required")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")

cat("=== Building Herald Master Rules CSV ===\n\n")

# -- Column schema (20 columns) -----------------------------------------------
COLS <- c("rule_id", "source", "source_document", "source_url", "authority",
          "standard", "ig_versions", "rule_type", "publisher_id",
          "conformance_rule_origin", "cited_guidance", "message", "description",
          "domains", "classes", "severity", "sensitivity", "executability",
          "status", "notes")

make_row <- function(...) {
  vals <- list(...)
  row <- setNames(as.list(rep("", length(COLS))), COLS)
  for (nm in names(vals)) row[[nm]] <- as.character(vals[[nm]] %||% "")
  as.data.frame(row, stringsAsFactors = FALSE)
}

# =============================================================================
# 1. CDISC Library API (engines/cdisc/)
# =============================================================================
cat("1. CDISC Library API...\n")
cdisc_dir <- file.path(repo_root, "engines", "cdisc")
cdisc_files <- list.files(cdisc_dir, pattern = "\\.yaml$", full.names = TRUE)

cdisc_rows <- lapply(cdisc_files, function(f) {
  tryCatch({
    r <- yaml::read_yaml(f)
    catalogs <- paste(unlist(r$herald$catalogs), collapse = "; ")
    std <- if (grepl("SDTM", catalogs)) "SDTM" else if (grepl("ADaM", catalogs)) "ADaM" else "SDTM"

    cg_ids <- c(); origins <- c(); cited <- c()
    for (auth in r$Authorities %||% list()) {
      for (s in auth$Standards %||% list()) {
        for (ref in s$References %||% list()) {
          rid <- ref$Rule_Identifier$Id %||% ""
          if (nzchar(rid)) cg_ids <- c(cg_ids, rid)
          o <- ref$Origin %||% ""
          if (nzchar(o)) origins <- c(origins, o)
          for (cit in ref$Citations %||% list()) {
            doc <- cit$Document %||% ""; sec <- cit$Section %||% ""
            if (nzchar(doc)) cited <- c(cited, paste0(doc, if (nzchar(sec)) paste0(" \u00A7", sec) else ""))
          }
        }
      }
    }

    make_row(
      rule_id = r$Core$Id, source = "CDISC Library API",
      source_document = "CDISC Conformance Rules (SDTMIG/ADaMIG)",
      source_url = "https://library.cdisc.org/api/mdr/rules",
      authority = "CDISC", standard = std, ig_versions = catalogs,
      rule_type = r$Rule_Type %||% "",
      publisher_id = paste(unique(cg_ids), collapse = "; "),
      conformance_rule_origin = paste(unique(origins), collapse = "; "),
      cited_guidance = paste(unique(cited), collapse = "; "),
      message = r$Outcome$Message %||% "", description = r$Description %||% "",
      domains = paste(unlist(r$Scope$Domains$Include), collapse = ", "),
      classes = paste(unlist(r$Scope$Classes$Include), collapse = ", "),
      sensitivity = r$Sensitivity %||% "",
      executability = r$Executability %||% "", status = r$Core$Status %||% ""
    )
  }, error = function(e) NULL)
})
cdisc_df <- do.call(rbind, Filter(Negate(is.null), cdisc_rows))
cat(sprintf("   %d rules\n", nrow(cdisc_df)))

# =============================================================================
# 2. FDA Validator Rules v1.6
# =============================================================================
cat("2. FDA Validator Rules v1.6...\n")
fda_f <- file.path(repo_root, ".local", "sources", "fda-validator-rules-v1.6.xlsx")
fda_raw <- readxl::read_excel(fda_f, sheet = "FDA Validator Rules v1.6",
                              skip = 1L, col_types = "text")
raw_names <- names(fda_raw)
names(fda_raw) <- c("rule_id", "publisher", "publisher_id", "message", "description",
                     "domains", paste0("ig_", seq_len(ncol(fda_raw) - 6L)))
ig_names <- gsub("\\r\\n", " ", raw_names[7:length(raw_names)])
fda_raw <- fda_raw[!is.na(fda_raw$rule_id) & nzchar(trimws(fda_raw$rule_id)), ]

fda_rows <- lapply(seq_len(nrow(fda_raw)), function(i) {
  row <- fda_raw[i, ]
  rid <- trimws(row$rule_id)
  prefix <- sub("\\d+.*$", "", rid)
  std <- if (prefix == "SE") "SEND" else "SDTM"
  ig_cols <- grep("^ig_", names(row))
  ig_app <- vapply(ig_cols, function(j) {
    if (!is.na(row[[j]]) && row[[j]] == "X") ig_names[j - 6L] else NA_character_
  }, character(1))
  ig_app <- ig_app[!is.na(ig_app)]

  make_row(
    rule_id = rid,
    source = "FDA Validator Rules v1.6 (December 2022)",
    source_document = "FDA Study Data Validator Rules v1.6",
    source_url = "https://www.fda.gov/industry/study-data-standards-resources/study-data-submission-cder-and-cber",
    authority = "FDA", standard = std,
    ig_versions = paste(ig_app, collapse = "; "),
    publisher_id = na_to_empty(trimws(row$publisher_id %||% "")),
    conformance_rule_origin = paste("Published by", na_to_empty(trimws(row$publisher %||% ""))),
    message = na_to_empty(trimws(row$message %||% "")),
    description = na_to_empty(trimws(row$description %||% "")),
    domains = na_to_empty(trimws(row$domains %||% "")),
    executability = "Reference", status = "Published",
    notes = paste("Publisher:", na_to_empty(trimws(row$publisher %||% "")))
  )
})
fda_df <- do.call(rbind, fda_rows)
cat(sprintf("   %d rules\n", nrow(fda_df)))

# =============================================================================
# 3. PMDA Validation Rules v6.0
# =============================================================================
cat("3. PMDA Validation Rules v6.0...\n")
pmda_f <- file.path(repo_root, ".local", "sources", "pmda-v6.0.zip")
tmp <- tempdir()
utils::unzip(pmda_f, exdir = tmp)
pmda_xlsx <- list.files(tmp, pattern = "ValidationRules.*\\.xlsx$", full.names = TRUE)[1]

parse_pmda_sheet <- function(xlsx, sheet, std_name) {
  d <- readxl::read_excel(xlsx, sheet = sheet, skip = 1L, col_types = "text")
  cn <- names(d); nc <- ncol(d)
  ver_idx <- grep("^\\d", cn)
  has_domain <- if (length(ver_idx) > 0) !4 %in% ver_idx else TRUE
  id_col <- 1; msg_col <- 2; desc_col <- 3
  if (has_domain) { dom_col <- 4; sev_col <- 5 } else { dom_col <- NA; sev_col <- 4 }
  notes_col <- nc
  d <- d[!is.na(d[[id_col]]) & d[[id_col]] != "RULE ID", ]

  lapply(seq_len(nrow(d)), function(i) {
    row <- d[i, ]
    ig_app <- vapply(ver_idx, function(vi) {
      if (!is.na(row[[vi]]) && row[[vi]] == "X") paste(std_name, cn[vi]) else NA_character_
    }, character(1))
    ig_app <- ig_app[!is.na(ig_app)]

    sev_raw <- na_to_empty(trimws(as.character(row[[sev_col]] %||% "")))
    sev_mapped <- switch(tolower(sev_raw), "reject"=,"rejection"= "Reject",
                         "error"= "Error", "warning"= "Warning", sev_raw)

    make_row(
      rule_id = trimws(as.character(row[[id_col]])),
      source = "PMDA Validation Rules v6.0 (March 2025)",
      source_document = paste("PMDA Study Data Validation Rules v6.0 -", sheet),
      source_url = "https://www.pmda.go.jp/english/review-services/reviews/0002.html",
      authority = "PMDA", standard = std_name,
      ig_versions = paste(ig_app, collapse = "; "),
      conformance_rule_origin = "PMDA (Japan)",
      message = na_to_empty(trimws(as.character(row[[msg_col]] %||% ""))),
      description = na_to_empty(trimws(as.character(row[[desc_col]] %||% ""))),
      domains = if (!is.na(dom_col)) na_to_empty(trimws(as.character(row[[dom_col]] %||% ""))) else "",
      severity = sev_mapped, executability = "Reference", status = "Published",
      notes = na_to_empty(trimws(as.character(row[[notes_col]] %||% "")))
    )
  })
}

pmda_df <- rbind(
  do.call(rbind, parse_pmda_sheet(pmda_xlsx, "SDTM Rules", "SDTM")),
  do.call(rbind, parse_pmda_sheet(pmda_xlsx, "ADaM Rules", "ADaM")),
  do.call(rbind, parse_pmda_sheet(pmda_xlsx, "Define-XML Rules", "Define-XML"))
)
cat(sprintf("   %d rules\n", nrow(pmda_df)))

# =============================================================================
# COMBINE (official sources only -- no P21 dependency)
# =============================================================================
master <- rbind(cdisc_df, fda_df, pmda_df)

cat(sprintf("\n=== MASTER CSV ===\n"))
cat(sprintf("Total: %d rules\n", nrow(master)))
cat(sprintf("\nBy source:\n"))
for (s in sort(unique(master$source))) {
  cat(sprintf("  %-50s %d\n", s, sum(master$source == s)))
}
cat(sprintf("\nBy authority:\n"))
for (a in sort(unique(master$authority))) {
  cat(sprintf("  %-15s %d\n", a, sum(master$authority == a)))
}
cat(sprintf("\nBy standard:\n"))
for (st in sort(unique(master$standard))) {
  cat(sprintf("  %-15s %d\n", st, sum(master$standard == st)))
}

out <- file.path(repo_root, "herald-master-rules.csv")
write.csv(master, out, row.names = FALSE, fileEncoding = "UTF-8")
cat(sprintf("\nWritten: %s (%d rows x %d cols)\n", out, nrow(master), ncol(master)))

cat("\nColumns:\n")
for (c in names(master)) cat(sprintf("  %s\n", c))
