#!/usr/bin/env Rscript
# =============================================================================
# build-configs.R -- Generate submission config profiles from engine rules
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) repo_root <- normalizePath(file.path(repo_root, "..", ".."))

if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml required")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")

configs_dir <- file.path(repo_root, "configs")
if (!dir.exists(configs_dir)) dir.create(configs_dir)

cat("=== Building Configs ===\n\n")

# --- Collect all rule IDs by engine -------------------------------------------

collect_ids <- function(engine_dir) {
  files <- list.files(file.path(repo_root, "engines", engine_dir),
                      pattern = "\\.yaml$", full.names = TRUE)
  ids <- vapply(files, function(f) {
    tryCatch({
      r <- yaml::read_yaml(f)
      r$id %||% r$Core$Id %||% ""
    }, error = function(e) "")
  }, character(1), USE.NAMES = FALSE)
  ids[nzchar(ids)]
}

cdisc_ids <- collect_ids("cdisc")
fda_ids   <- collect_ids("fda")
pmda_ids  <- collect_ids("pmda")
ct_ids    <- collect_ids("ct")

cat(sprintf("  CDISC: %d IDs\n", length(cdisc_ids)))
cat(sprintf("  FDA:   %d IDs\n", length(fda_ids)))
cat(sprintf("  PMDA:  %d IDs\n", length(pmda_ids)))
cat(sprintf("  CT:    %d IDs\n", length(ct_ids)))

# --- Filter by standard/IG version -------------------------------------------

# PMDA IDs: filter by reading provenance.ig_versions
filter_pmda_by_ig <- function(ig_pattern) {
  files <- list.files(file.path(repo_root, "engines", "pmda"),
                      pattern = "\\.yaml$", full.names = TRUE)
  ids <- c()
  for (f in files) {
    tryCatch({
      r <- yaml::read_yaml(f)
      ig <- paste(unlist(r$provenance$ig_versions), collapse = " ")
      rid <- r$id %||% ""
      if (nzchar(rid) && (grepl(ig_pattern, ig) || length(r$provenance$ig_versions) == 0)) {
        ids <- c(ids, rid)
      }
    }, error = function(e) NULL)
  }
  ids
}

# FDA IDs: filter by standard field
filter_fda_by_std <- function(std_pattern) {
  files <- list.files(file.path(repo_root, "engines", "fda"),
                      pattern = "\\.yaml$", full.names = TRUE)
  ids <- c()
  for (f in files) {
    tryCatch({
      r <- yaml::read_yaml(f)
      rid <- r$Core$Id %||% r$id %||% ""
      std <- r$Standard %||% ""
      if (nzchar(rid) && grepl(std_pattern, std, ignore.case = TRUE)) {
        ids <- c(ids, rid)
      }
    }, error = function(e) NULL)
  }
  ids
}

# --- Write config JSON --------------------------------------------------------

write_config <- function(config_id, authority, standard, version, source_docs, rule_ids) {
  cfg <- list(
    config_id = config_id,
    authority = authority,
    standard = standard,
    version = version,
    source_documents = as.list(source_docs),
    ct_package = if (grepl("SDTM", standard)) "sdtm-ct" else if (grepl("ADaM", standard)) "adam-ct" else "sdtm-ct",
    rule_ids = as.list(sort(unique(rule_ids))),
    severity_overrides = list()
  )
  out <- file.path(configs_dir, paste0(config_id, ".json"))
  writeLines(jsonlite::toJSON(cfg, auto_unbox = TRUE, pretty = TRUE), out)
  cat(sprintf("  %s: %d rules\n", config_id, length(cfg$rule_ids)))
}

# --- Generate configs ---------------------------------------------------------

fda_sdtm <- filter_fda_by_std("SDTM")
pmda_sdtm_33 <- filter_pmda_by_ig("3\\.3")
pmda_sdtm_32 <- filter_pmda_by_ig("3\\.2")
pmda_adam_11 <- filter_pmda_by_ig("1\\.1")

cat("\nWriting configs...\n")

write_config("fda-sdtm-ig-3.3", "FDA", "SDTM-IG", "3.3",
             c("CDISC SDTM-IG v3.3", "FDA Validator Rules v1.6"),
             c(cdisc_ids, fda_sdtm, ct_ids))

write_config("fda-sdtm-ig-3.2", "FDA", "SDTM-IG", "3.2",
             c("CDISC SDTM-IG v3.2", "FDA Validator Rules v1.6"),
             c(cdisc_ids, fda_sdtm, ct_ids))

write_config("fda-adam-ig-1.1", "FDA", "ADaM-IG", "1.1",
             c("CDISC ADaM-IG v1.1", "FDA Validator Rules v1.6"),
             c(fda_sdtm, ct_ids))

write_config("fda-adam-ig-1.2", "FDA", "ADaM-IG", "1.2",
             c("CDISC ADaM-IG v1.2", "FDA Validator Rules v1.6"),
             c(fda_sdtm, ct_ids))

write_config("fda-define-xml-2.1", "FDA", "Define-XML", "2.1",
             c("CDISC Define-XML v2.1", "FDA Validator Rules v1.6"),
             c(fda_ids, ct_ids))

write_config("pmda-sdtm-ig-3.3", "PMDA", "SDTM-IG", "3.3",
             c("CDISC SDTM-IG v3.3", "PMDA Validation Rules v6.0"),
             c(cdisc_ids, pmda_sdtm_33, ct_ids))

write_config("pmda-sdtm-ig-3.2", "PMDA", "SDTM-IG", "3.2",
             c("CDISC SDTM-IG v3.2", "PMDA Validation Rules v6.0"),
             c(cdisc_ids, pmda_sdtm_32, ct_ids))

write_config("pmda-adam-ig-1.1", "PMDA", "ADaM-IG", "1.1",
             c("CDISC ADaM-IG v1.1", "PMDA Validation Rules v6.0"),
             c(pmda_adam_11, ct_ids))

write_config("pmda-define-xml-2.1", "PMDA", "Define-XML", "2.1",
             c("CDISC Define-XML v2.1", "PMDA Validation Rules v6.0"),
             c(pmda_ids, ct_ids))

write_config("all", "Combined", "All", "2026.2",
             c("All herald rules"),
             c(cdisc_ids, fda_ids, pmda_ids, ct_ids))

cat("\nDone.\n")
