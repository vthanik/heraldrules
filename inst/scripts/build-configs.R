#!/usr/bin/env Rscript
# =============================================================================
# build-configs.R -- Generate submission config profiles from engine rules
# =============================================================================
#
# ADR-002: Version scope lives in herald.ig_versions on each rule YAML.
# ADR-003: Later version = superset (1.2 includes all rules tagged "1.1" or "1.2").
# ADR-004: PMDA rules filter by provenance.standard, not ig_versions (always empty).
# ADR-005: Each config includes exactly one authority (FDA or PMDA), never both.
#
# See .claude/plans/ for full decision record.
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) repo_root <- normalizePath(file.path(repo_root, "..", ".."))

if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml required")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")

configs_dir <- file.path(repo_root, "configs")
if (!dir.exists(configs_dir)) dir.create(configs_dir)

cat("=== Building Configs ===\n\n")

# --- Collect all rule IDs by engine (unfiltered) ------------------------------

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

fda_ids    <- collect_ids("fda")
ct_ids     <- collect_ids("ct")
herald_ids <- collect_ids("herald")
pmda_ids   <- collect_ids("pmda")   # all PMDA (used by pmda-define-xml and "all" config)

cat(sprintf("  FDA:    %d IDs\n", length(fda_ids)))
cat(sprintf("  PMDA:   %d IDs (all standards)\n", length(pmda_ids)))
cat(sprintf("  CT:     %d IDs\n", length(ct_ids)))
cat(sprintf("  Herald: %d IDs\n", length(herald_ids)))

# --- CDISC: version-aware ADaM filtering (ADR-002, ADR-003) -------------------
#
# SDTM CORE rules have no ig_versions (null = applies to all).
# ADaM-NNN rules carry ig_versions: ["1.1"] or ["1.1","1.2"] or ["1.2"].
# Filter: include rule if ig_version is in its ig_versions list, or if
#         ig_versions is null (backward compat for SDTM/SEND CORE rules).

filter_cdisc_by_ig <- function(ig_version) {
  files <- list.files(file.path(repo_root, "engines", "cdisc"),
                      pattern = "\\.yaml$", full.names = TRUE)
  ids <- c()
  for (f in files) {
    tryCatch({
      r <- yaml::read_yaml(f)
      rid <- r$Core$Id %||% r$id %||% ""
      if (!nzchar(rid)) next
      ig_vers <- unlist(r$herald$ig_versions)
      # null ig_versions = applies to all versions (SDTM/SEND CORE rules)
      if (is.null(ig_vers) || ig_version %in% ig_vers) {
        ids <- c(ids, rid)
      }
    }, error = function(e) NULL)
  }
  ids
}

# --- PMDA: filter by standard field (ADR-004) ---------------------------------
#
# All 1,041 PMDA rules have empty ig_versions but populate provenance.standard
# with "ADaM", "SDTM", or "Define-XML". Filter on that field.
# ig_pattern is applied only if ig_versions is populated (future-proofing).

filter_pmda <- function(std_name, ig_pattern = NULL) {
  files <- list.files(file.path(repo_root, "engines", "pmda"),
                      pattern = "\\.yaml$", full.names = TRUE)
  ids <- c()
  for (f in files) {
    tryCatch({
      r <- yaml::read_yaml(f)
      rid <- r$id %||% ""
      if (!nzchar(rid)) next
      std <- r$provenance$standard %||% r$standard %||% ""
      if (!grepl(std_name, std, ignore.case = TRUE)) next
      # If ig_pattern given and ig_versions is populated, apply version filter
      if (!is.null(ig_pattern)) {
        ig <- paste(unlist(r$provenance$ig_versions), collapse = " ")
        if (nzchar(ig) && !grepl(ig_pattern, ig)) next
      }
      ids <- c(ids, rid)
    }, error = function(e) NULL)
  }
  ids
}

# --- FDA IDs: filter by standard field ----------------------------------------

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
  # ADR-007: Detect duplicates explicitly before deduplication -- never silently collapse
  dupes <- rule_ids[duplicated(rule_ids)]
  if (length(dupes) > 0L) {
    warning(sprintf("  %s: %d duplicate rule ID(s) found and removed: %s",
                    config_id, length(dupes),
                    paste(head(unique(dupes), 10L), collapse = ", ")))
  }
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

# --- Build version-specific rule sets -----------------------------------------

cat("\nBuilding version-filtered rule sets...\n")

fda_sdtm       <- filter_fda_by_std("SDTM")
cdisc_all      <- filter_cdisc_by_ig("1.1")   # all rules: SDTM CORE + ADaM 1.1 (no ig_versions = included)
cdisc_adam_11  <- filter_cdisc_by_ig("1.1")   # ADaM 1.1 config: same as cdisc_all (SDTM rules pass through)
cdisc_adam_12  <- filter_cdisc_by_ig("1.2")   # ADaM 1.2 config: superset of 1.1 + new 1.2 rules
pmda_sdtm_33   <- filter_pmda("SDTM", "3\\.3")
pmda_sdtm_32   <- filter_pmda("SDTM", "3\\.2")
pmda_adam_11   <- filter_pmda("ADaM")

cat(sprintf("  CDISC all/1.1:  %d IDs\n", length(cdisc_adam_11)))
cat(sprintf("  CDISC adam_1.2: %d IDs\n", length(cdisc_adam_12)))
cat(sprintf("  FDA SDTM:       %d IDs\n", length(fda_sdtm)))
cat(sprintf("  PMDA SDTM 3.3:  %d IDs\n", length(pmda_sdtm_33)))
cat(sprintf("  PMDA SDTM 3.2:  %d IDs\n", length(pmda_sdtm_32)))
cat(sprintf("  PMDA ADaM 1.1:  %d IDs\n", length(pmda_adam_11)))

# --- Generate configs (ADR-005: one authority per config) ---------------------

cat("\nWriting configs...\n")

write_config("fda-sdtm-ig-3.3", "FDA", "SDTM-IG", "3.3",
             c("CDISC SDTM-IG v3.3", "FDA Validator Rules v1.6", "Herald custom rules"),
             c(cdisc_all, fda_sdtm, ct_ids, herald_ids))

write_config("fda-sdtm-ig-3.2", "FDA", "SDTM-IG", "3.2",
             c("CDISC SDTM-IG v3.2", "FDA Validator Rules v1.6", "Herald custom rules"),
             c(cdisc_all, fda_sdtm, ct_ids, herald_ids))

# FDA ADaM configs: use version-filtered CDISC rules (ADR-003 superset)
# Note: FDA has no ADaM-specific validator rules; fda_sdtm covers ADaM datasets too
write_config("fda-adam-ig-1.1", "FDA", "ADaM-IG", "1.1",
             c("CDISC ADaM-IG v1.1", "FDA Validator Rules v1.6", "Herald custom rules"),
             c(cdisc_adam_11, fda_sdtm, ct_ids, herald_ids))

write_config("fda-adam-ig-1.2", "FDA", "ADaM-IG", "1.2",
             c("CDISC ADaM-IG v1.2", "FDA Validator Rules v1.6", "Herald custom rules"),
             c(cdisc_adam_12, fda_sdtm, ct_ids, herald_ids))

write_config("fda-define-xml-2.1", "FDA", "Define-XML", "2.1",
             c("CDISC Define-XML v2.1", "FDA Validator Rules v1.6", "Herald custom rules"),
             c(fda_ids, ct_ids, herald_ids))

write_config("pmda-sdtm-ig-3.3", "PMDA", "SDTM-IG", "3.3",
             c("CDISC SDTM-IG v3.3", "PMDA Validation Rules v6.0", "Herald custom rules"),
             c(cdisc_all, pmda_sdtm_33, ct_ids, herald_ids))

write_config("pmda-sdtm-ig-3.2", "PMDA", "SDTM-IG", "3.2",
             c("CDISC SDTM-IG v3.2", "PMDA Validation Rules v6.0", "Herald custom rules"),
             c(cdisc_all, pmda_sdtm_32, ct_ids, herald_ids))

write_config("pmda-adam-ig-1.1", "PMDA", "ADaM-IG", "1.1",
             c("CDISC ADaM-IG v1.1", "PMDA Validation Rules v6.0", "Herald custom rules"),
             c(cdisc_adam_11, pmda_adam_11, ct_ids, herald_ids))

write_config("pmda-define-xml-2.1", "PMDA", "Define-XML", "2.1",
             c("CDISC Define-XML v2.1", "PMDA Validation Rules v6.0", "Herald custom rules"),
             c(filter_pmda("Define"), ct_ids, herald_ids))

write_config("all", "Combined", "All", "2026.2",
             c("All herald rules"),
             c(filter_cdisc_by_ig("1.2"), fda_ids, pmda_ids, ct_ids, herald_ids))

cat("\nDone.\n")
