#!/usr/bin/env Rscript
# =============================================================================
# p21-coverage/check.R -- Pinnacle 21 rule coverage audit
# =============================================================================
#
# Reads two P21 Community validator reports (HBPD03 SDTM + ADaM) and joins
# every distinct Pinnacle 21 ID against herald-master-rules.csv. Reports:
#
#   * Total P21 IDs in the two reports (target = 100% coverage)
#   * IDs with an executable herald rule today
#   * IDs with only Partially Executable / Reference variants
#   * IDs with no herald mapping at all (must add brand-new YAML)
#
# Runs against the CURRENT state of heraldrules -- no herald package needed.
# Use between commits to track convergence toward 100% executable P21 parity.
#
# Exit code 0 when every P21 ID resolves to Fully Executable.
# Exit code 1 otherwise (with a breakdown printed).
#
# Usage:
#   Rscript inst/benchmarks/p21-coverage/check.R
# Optional env vars:
#   HERALDRULES_P21_SDTM -- override path to SDTM P21 xlsx
#   HERALDRULES_P21_ADAM -- override path to ADaM P21 xlsx
# =============================================================================

suppressPackageStartupMessages({
  for (pkg in c("readxl")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Missing required package: ", pkg)
    }
  }
})

# Resolve repo root: prefer the directory where this script lives, walk
# up to the repo root. Falls back to getwd() when run interactively.
.this_script <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  if (length(hit)) return(sub("^--file=", "", hit[1L]))
  NA_character_
}
.here <- .this_script()
repo_root <- if (!is.na(.here) && nzchar(.here)) {
  normalizePath(file.path(dirname(.here), "..", "..", ".."), mustWork = FALSE)
} else {
  getwd()
}
if (!file.exists(file.path(repo_root, "herald-master-rules.csv"))) {
  # Best-effort fallback when invoked from the repo root directly.
  repo_root <- getwd()
}

default_sdtm <- "/Users/vignesh/projects/data/HBPD03/sdtm/pinnacle21-report-2026-04-18T05-26-03-776.xlsx"
default_adam <- "/Users/vignesh/projects/data/HBPD03/adam/pinnacle21-report-2026-04-18T03-44-11-646.xlsx"
sdtm_path <- Sys.getenv("HERALDRULES_P21_SDTM", default_sdtm)
adam_path <- Sys.getenv("HERALDRULES_P21_ADAM", default_adam)

for (p in c(sdtm_path, adam_path)) {
  if (!file.exists(p)) {
    cat("ERROR: P21 report not found:", p, "\n", file = stderr())
    quit(status = 2L)
  }
}

master_csv <- file.path(repo_root, "herald-master-rules.csv")
if (!file.exists(master_csv)) {
  cat("ERROR: master rules CSV not found:", master_csv, "\n", file = stderr())
  quit(status = 2L)
}

# -- load --------------------------------------------------------------------

sdtm_ids <- unique(readxl::read_excel(sdtm_path, sheet = "Rules")$`Pinnacle 21 ID`)
adam_ids <- unique(readxl::read_excel(adam_path, sheet = "Rules")$`Pinnacle 21 ID`)
all_p21 <- unique(c(sdtm_ids, adam_ids))

m <- read.csv(master_csv, stringsAsFactors = FALSE)

# -- per-P21-ID best status --------------------------------------------------

best_status <- function(p21_id) {
  rows <- m[m$p21_id == p21_id, , drop = FALSE]
  if (nrow(rows) == 0L) return("UNMAPPED")
  if (any(rows$executability == "Fully Executable")) return("Fully Executable")
  if (any(rows$executability == "Hardcoded")) return("Hardcoded")
  if (any(grepl("^Partially Executable", rows$executability))) return("Partially Executable")
  if (any(rows$executability == "Reference")) return("Reference")
  "OTHER"
}

status <- vapply(all_p21, best_status, character(1))
tab <- table(status)

# -- Effective coverage: Partial-with-real-check also runs -------------------
# A Partial P21 ID is "effectively running" when at least one of its herald
# rule YAMLs ships a real check: block (any operator, including
# manual_review which fires advisory findings). Only truly blocked rules
# are those with best_status Reference or UNMAPPED.
#
# We don't re-parse every YAML; the manifest / configs already know which
# rules get included in a runnable config. Instead we use a simpler proxy:
# a rule counts as "effectively running" iff its p21_id has any herald row
# whose executability is in the RUNNABLE allow-list (Fully Executable,
# Hardcoded, or any Partially Executable flavour).
.runnable_execs <- c(
  "Fully Executable", "Hardcoded",
  "Partially Executable",
  "Partially Executable - Possible Overreporting",
  "Partially Executable - Possible Underreporting"
)
is_effectively_running <- function(p21_id) {
  rows <- m[m$p21_id == p21_id, , drop = FALSE]
  any(rows$executability %in% .runnable_execs)
}
eff_running <- vapply(all_p21, is_effectively_running, logical(1))

# -- report -------------------------------------------------------------------

cat("============================================================\n")
cat(" P21 rule coverage audit (HBPD03 SDTM + ADaM)\n")
cat("============================================================\n")
cat(sprintf(" SDTM P21 rules: %d\n", length(sdtm_ids)))
cat(sprintf(" ADaM P21 rules: %d\n", length(adam_ids)))
cat(sprintf(" Overlap       : %d\n", length(intersect(sdtm_ids, adam_ids))))
cat(sprintf(" Unique total  : %d\n", length(all_p21)))
cat("------------------------------------------------------------\n")
cat(" Best available herald executability per P21 ID:\n")
for (k in names(tab)) {
  cat(sprintf("   %-24s %4d  (%5.1f%%)\n", k, tab[[k]], 100 * tab[[k]] / length(all_p21)))
}
cat("------------------------------------------------------------\n")
cat(sprintf(" STRICT coverage    (Fully Executable only): %d / %d  (%5.1f%%)\n",
            sum(status %in% c("Fully Executable", "Hardcoded")),
            length(all_p21),
            100 * sum(status %in% c("Fully Executable", "Hardcoded")) / length(all_p21)))
cat(sprintf(" EFFECTIVE coverage (runs + produces findings): %d / %d  (%5.1f%%)\n",
            sum(eff_running),
            length(all_p21),
            100 * sum(eff_running) / length(all_p21)))
cat("------------------------------------------------------------\n")

need_work <- names(status[!status %in% c("Fully Executable", "Hardcoded")])
cat(sprintf(" Need conversion to Fully Executable: %d\n", length(need_work)))

if (length(need_work) > 0L) {
  cat("\n First 30 P21 IDs needing work:\n")
  by_status <- split(need_work, status[need_work])
  for (k in names(by_status)) {
    ids <- sort(by_status[[k]])
    cat(sprintf("   %s (%d):\n", k, length(ids)))
    show <- head(ids, 30L)
    for (id in show) cat("     ", id, "\n")
    if (length(ids) > 30L) cat(sprintf("     ... and %d more\n", length(ids) - 30L))
  }
}

cat("============================================================\n")
if (length(need_work) == 0L) {
  cat(" RESULT: 100% P21 coverage -- every ID maps to Fully Executable.\n")
  quit(status = 0L)
} else {
  pct <- 100 * (length(all_p21) - length(need_work)) / length(all_p21)
  cat(sprintf(" RESULT: %.1f%% coverage. %d IDs need work.\n", pct, length(need_work)))
  quit(status = 1L)
}
