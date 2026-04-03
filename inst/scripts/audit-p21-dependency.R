#!/usr/bin/env Rscript
# =============================================================================
# audit-p21-dependency.R -- Audit P21 provenance in herald-original rules
# =============================================================================
#
# Scans all rules/ YAML files for P21 provenance references and reports
# how many are derived from Pinnacle 21 vs truly herald-original.
#
# Usage:
#   Rscript inst/scripts/audit-p21-dependency.R           # Summary report
#   Rscript inst/scripts/audit-p21-dependency.R --csv      # Export CSV
#   Rscript inst/scripts/audit-p21-dependency.R --verbose   # Show each rule
#
# Output:
#   Console report + optional audit-p21-dependency.csv
#
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

args <- commandArgs(trailingOnly = TRUE)
csv_out <- "--csv" %in% args
verbose <- "--verbose" %in% args

# --- Locate repository root ---------------------------------------------------

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) {
  repo_root <- normalizePath(file.path(repo_root, "..", ".."))
}

rules_dir <- file.path(repo_root, "rules")

if (!dir.exists(rules_dir)) {
  stop(sprintf("Rules directory not found: %s", rules_dir), call. = FALSE)
}

if (!requireNamespace("yaml", quietly = TRUE)) {
  stop("The yaml package is required: install.packages('yaml')", call. = FALSE)
}

cat("=== P21 Dependency Audit ===\n\n")

# --- Discover rule files ------------------------------------------------------

yaml_files <- list.files(rules_dir, pattern = "\\.yaml$",
                         recursive = TRUE, full.names = TRUE)
cat(sprintf("Scanning %d rule files in rules/\n\n", length(yaml_files)))

# --- Scan each file -----------------------------------------------------------

results <- vector("list", length(yaml_files))

for (i in seq_along(yaml_files)) {
  f <- yaml_files[i]
  tryCatch({
    rule <- yaml::read_yaml(f)

    prov <- rule$provenance %||% list()

    results[[i]] <- data.frame(
      file      = basename(f),
      rule_id   = rule$id %||% "",
      standard  = rule$standard %||% "",
      category  = rule$category %||% "",
      p21_id    = prov$p21_id %||% "",
      core_id   = prov$core_id %||% "",
      cg_ids    = paste(unlist(prov$cg_ids) %||% "", collapse = ";"),
      fda_ids   = paste(unlist(prov$fda_ids) %||% "", collapse = ";"),
      source_doc = prov$source_doc %||% "",
      has_p21   = !is.null(prov$p21_id) && nzchar(prov$p21_id %||% ""),
      has_core  = !is.null(prov$core_id) && nzchar(prov$core_id %||% ""),
      has_cg    = !is.null(prov$cg_ids) && length(prov$cg_ids) > 0L,
      stringsAsFactors = FALSE
    )

    if (verbose) {
      r <- results[[i]]
      flag <- if (r$has_p21 && !r$has_core) "P21-ONLY" else
              if (r$has_p21 && r$has_core) "CROSS-REF" else "ORIGINAL"
      cat(sprintf("  %-15s %-10s %-8s %s\n", r$rule_id, r$standard, flag,
                  substr(rule$description %||% "", 1, 50)))
    }
  }, error = function(e) {
    cat(sprintf("  WARNING: Failed to parse %s: %s\n", basename(f),
                conditionMessage(e)))
    results[[i]] <<- NULL
  })
}

df <- do.call(rbind, Filter(Negate(is.null), results))

# --- Report -------------------------------------------------------------------

total <- nrow(df)
p21_total    <- sum(df$has_p21)
p21_and_core <- sum(df$has_p21 & df$has_core)
p21_only     <- sum(df$has_p21 & !df$has_core)
no_p21       <- sum(!df$has_p21)

cat(sprintf("\n=== Results ===\n\n"))
cat(sprintf("  Total rules scanned:         %d\n", total))
cat(sprintf("\n  P21 References:\n"))
cat(sprintf("    With p21_id:               %d (%4.1f%%)\n",
            p21_total, 100 * p21_total / total))
cat(sprintf("    With p21_id + core_id:     %d  (cross-referenced)\n", p21_and_core))
cat(sprintf("    With p21_id only:          %d  (P21-dependent, needs review)\n", p21_only))
cat(sprintf("    Without p21_id:            %d  (independent)\n", no_p21))

# By standard
cat(sprintf("\n  By standard:\n"))
for (std in sort(unique(df$standard))) {
  sub_df <- df[df$standard == std, ]
  n_p21 <- sum(sub_df$has_p21)
  cat(sprintf("    %-12s %4d / %4d (%4.1f%%) have p21_id\n",
              paste0(std, ":"), n_p21, nrow(sub_df),
              100 * n_p21 / nrow(sub_df)))
}

# By category
cat(sprintf("\n  By category:\n"))
for (cat_name in sort(unique(df$category))) {
  sub_df <- df[df$category == cat_name, ]
  n_p21 <- sum(sub_df$has_p21)
  cat(sprintf("    %-20s %4d / %4d (%4.1f%%)\n",
              paste0(cat_name, ":"), n_p21, nrow(sub_df),
              100 * n_p21 / nrow(sub_df)))
}

# P21-only rules needing review
if (p21_only > 0L) {
  cat(sprintf("\n  P21-only rules (no CORE cross-reference, highest priority for review):\n"))
  p21_only_df <- df[df$has_p21 & !df$has_core, ]
  show_n <- min(20L, nrow(p21_only_df))
  for (j in seq_len(show_n)) {
    r <- p21_only_df[j, ]
    cat(sprintf("    %-15s %-6s %-12s p21=%s\n",
                r$rule_id, r$p21_id, r$standard, r$p21_id))
  }
  if (nrow(p21_only_df) > 20L) {
    cat(sprintf("    ... and %d more (see CSV for full list)\n",
                nrow(p21_only_df) - 20L))
  }
}

# --- CSV export ---------------------------------------------------------------

if (csv_out) {
  csv_path <- file.path(repo_root, "audit-p21-dependency.csv")
  write.csv(df, csv_path, row.names = FALSE)
  cat(sprintf("\n  CSV exported: %s\n", csv_path))
}

cat("\nDone.\n")
