#!/usr/bin/env Rscript
# =============================================================================
# build-cran-package.R -- Compile catalog artifacts into inst/rules/ for CRAN
# =============================================================================
#
# Shrinks the 26 MB authoring layout into a ~2 MB CRAN-ready payload by:
#
#   1. Reading every YAML under engines/ and rewriting it as a compact
#      rule record (rule_id, p21_id, source, engine, standard, ig_versions,
#      scope, severity, message, description, operations, check).
#   2. Packing the records that belong to each config (from configs/*.json)
#      into a single list and writing `inst/rules/catalog/<config>.json.gz`.
#   3. Reading ct/sdtm-ct.json + ct/adam-ct.json and serialising each as
#      `inst/rules/ct/<pkg>-ct.rds` with `compress = "xz"`.
#   4. Compressing the p21-id map and manifest into inst/rules/.
#
# Runs after build-configs.R + build-manifest.R. Loose YAMLs under engines/
# are .Rbuildignored, so the resulting tarball carries only inst/rules/.
#
# Usage: Rscript inst/scripts/build-cran-package.R
# =============================================================================

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

if (!requireNamespace("yaml",     quietly = TRUE)) stop("yaml required")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) {
  repo_root <- normalizePath(file.path(repo_root, "..", ".."))
}

out_rules <- file.path(repo_root, "inst", "rules")
out_ct    <- file.path(out_rules, "ct")
dir.create(out_rules, recursive = TRUE, showWarnings = FALSE)
dir.create(out_ct,    recursive = TRUE, showWarnings = FALSE)
# Clean any stale catalog/ directory from the previous (bulky) layout
unlink(file.path(out_rules, "catalog"), recursive = TRUE)

cat("=== Building CRAN-package artifacts ===\n\n")

# -- Helper: read every engine YAML once, indexed by rule_id ------------------
read_all_rules <- function() {
  engines <- c("cdisc", "ct", "fda", "herald", "pmda")
  out <- list()
  for (eng in engines) {
    files <- list.files(file.path(repo_root, "engines", eng),
                        pattern = "\\.yaml$", full.names = TRUE,
                        recursive = TRUE)
    cat(sprintf("  %-7s %4d YAMLs\n", eng, length(files)))
    for (f in files) {
      r <- tryCatch(yaml::read_yaml(f), error = function(e) NULL)
      if (is.null(r)) next
      # PascalCase (CDISC/FDA) vs lowercase (PMDA/CT/Herald) schema coexistence
      rid <- r$Core$Id %||% r$id %||% ""
      if (!nzchar(rid)) next
      out[[rid]] <- list(
        rule_id       = rid,
        engine        = eng,
        file          = sub(paste0("^", repo_root, "/"), "", f),
        source        = r$Source %||% r$provenance$source %||%
                        r$Authorities[[1]]$Organization %||% "",
        standard      = r$Standard %||% r$provenance$standard %||%
                        r$standard %||% "",
        ig_versions   = unlist(r$`IG Versions` %||% r$ig_versions %||%
                               r$herald$ig_versions %||% list()),
        rule_type     = r$`Rule Type` %||% r$category %||%
                        r$rule_type %||% "",
        severity      = r$Outcome$Severity %||% r$outcome$severity %||%
                        r$Sensitivity %||% r$sensitivity %||% "Error",
        sensitivity   = r$Sensitivity %||% r$sensitivity %||% "",
        executability = r$Executability %||% r$executability %||% "",
        status        = r$Core$Status %||% r$status %||% "",
        message       = r$Outcome$Message %||% r$outcome$message %||%
                        r$Message %||% r$message %||% "",
        description   = r$Description %||% r$description %||% "",
        domains       = unlist(r$Scope$Domains$Include %||%
                               r$scope$domains %||% list()),
        classes       = unlist(r$Scope$Classes$Include %||%
                               r$scope$classes %||% list()),
        publisher_ids = unlist(strsplit(r$`Publisher ID` %||%
                                        r$publisher_id %||% "",
                                        "[,;] *")),
        operations    = r$Operations %||% r$operations %||% list(),
        check         = r$Check %||% r$check %||% list()
      )
    }
  }
  out
}

# -- Helper: derive P21 display id from a rule_id -----------------------------
# Same algorithm as inst/scripts/build-master-csv.R::derive_p21_id(), plus
# one extra case: strip the "FDAV-" prefix off CDISC CORE-style IDs so the
# FDA Validator rules with Core.Id = "FDAV-SD0001" also map to SD0001.
derive_p21_id <- function(rule_id) {
  rid <- trimws(as.character(rule_id))
  if (!length(rid) || is.na(rid) || !nzchar(rid)) return("")
  if (grepl("^FDAV-(SD|AD|SE|DD|CV|TS|OD|HM|CT2)[0-9]+[A-Z]?$", rid)) {
    return(sub("^FDAV-", "", rid))
  }
  if (grepl("^(SD|AD|SE|DD|CV|TS|OD|HM)[0-9]+[A-Z]?$", rid)) return(rid)
  if (grepl("^CT2[0-9]+$", rid)) return(rid)
  m <- regmatches(rid, regexec("^ADaM-([0-9]+)(-SD)?$", rid))[[1]]
  if (length(m) == 3L) return(sprintf("AD%04d", as.integer(m[2])))
  ""
}

# -- Helper: look up p21_id for a rule ----------------------------------------
# Prefers the CSV-declared p21_id where present; falls back to the derivation
# above so FDA-engine rules (whose Core.Id is "FDAV-*" but whose CSV row
# doesn't exist by that name) still get a non-empty p21_id.
build_p21_lookup <- function(all_rules) {
  csv <- utils::read.csv(file.path(repo_root, "herald-master-rules.csv"),
                         stringsAsFactors = FALSE, check.names = FALSE)
  csv_lookup <- if ("p21_id" %in% names(csv)) {
    split_ids <- split(csv$p21_id, csv$rule_id)
    lapply(split_ids, function(v) {
      v <- v[nzchar(v)]
      if (length(v) == 0L) "" else v[[1L]]
    })
  } else {
    list()
  }
  # Ensure every YAML rule_id gets an entry; derive when CSV empty
  out <- list()
  for (rid in names(all_rules)) {
    fromcsv <- csv_lookup[[rid]] %||% ""
    out[[rid]] <- if (nzchar(fromcsv)) fromcsv else derive_p21_id(rid)
  }
  out
}

# -- 1a. Flat rule database: every record once (deduped across configs) -----
compile_rules_db <- function(all_rules, p21_lookup) {
  for (rid in names(all_rules)) {
    all_rules[[rid]]$p21_id <- p21_lookup[[rid]] %||% ""
  }
  # Drop the file field (authoring path; runtime doesn't need it)
  all_rules <- lapply(all_rules, function(r) { r$file <- NULL; r })
  out <- file.path(repo_root, "inst", "rules", "rules.json.gz")
  gz <- gzfile(out, "wb", compression = 9L)
  writeLines(jsonlite::toJSON(all_rules, auto_unbox = TRUE), gz)
  close(gz)
  cat(sprintf("  rules.json.gz           %4d rules  %6.1f KB\n",
              length(all_rules), file.info(out)$size / 1024))
}

# -- 1b. Tiny id-only config JSONs (list of rule_ids per config) -------------
compile_configs <- function() {
  out_dir <- file.path(repo_root, "inst", "rules", "configs")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  cfg_files <- list.files(file.path(repo_root, "configs"),
                          pattern = "\\.json$", full.names = TRUE)
  for (cf in cfg_files) {
    cfg <- jsonlite::read_json(cf)
    slim <- list(
      config_id  = cfg$config_id,
      authority  = cfg$authority,
      standard   = cfg$standard,
      version    = cfg$version,
      rule_ids   = cfg$rule_ids
    )
    cfg_id <- tools::file_path_sans_ext(basename(cf))
    out <- file.path(out_dir, paste0(cfg_id, ".json.gz"))
    gz <- gzfile(out, "wb", compression = 9L)
    writeLines(jsonlite::toJSON(slim, auto_unbox = TRUE), gz)
    close(gz)
    cat(sprintf("  %-25s %4d ids    %6.1f KB\n",
                cfg_id, length(unlist(slim$rule_ids)),
                file.info(out)$size / 1024))
  }
}

# -- 2. CT terms -> xz-compressed RDS ----------------------------------------
compile_ct <- function() {
  for (pkg in c("sdtm", "adam")) {
    raw <- file.path(repo_root, "ct", paste0(pkg, "-ct.json"))
    if (!file.exists(raw)) {
      cat(sprintf("  (skip) %s-ct.json not found\n", pkg))
      next
    }
    terms <- jsonlite::read_json(raw, simplifyVector = TRUE)
    out <- file.path(out_ct, paste0(pkg, "-ct.rds"))
    saveRDS(terms, out, compress = "xz")
    cat(sprintf("  %-20s %6.1f KB\n", basename(out),
                file.info(out)$size / 1024))
  }
}

# -- 3. P21 id map -> gzipped CSV --------------------------------------------
compile_p21_map <- function() {
  csv_path <- file.path(repo_root, "herald-master-rules.csv")
  csv <- utils::read.csv(csv_path, stringsAsFactors = FALSE,
                         check.names = FALSE)
  keep <- unique(csv[, c("rule_id", "p21_id")])
  out <- file.path(repo_root, "inst", "rules", "p21-id-map.csv.gz")
  gz <- gzfile(out, "wb", compression = 9L)
  utils::write.csv(keep, gz, row.names = FALSE)
  close(gz)
  cat(sprintf("  %-30s %6.1f KB\n", "p21-id-map.csv.gz",
              file.info(out)$size / 1024))
}

# -- 4. Copy manifest + master-rules (compressed) ----------------------------
compile_manifest <- function() {
  src <- file.path(repo_root, "manifest.json")
  dst <- file.path(repo_root, "inst", "rules", "manifest.json")
  file.copy(src, dst, overwrite = TRUE)
  cat(sprintf("  %-30s %6.1f KB\n", "manifest.json",
              file.info(dst)$size / 1024))
}

# --- Run ---------------------------------------------------------------------
cat("Reading engine YAMLs...\n")
all_rules   <- read_all_rules()
cat(sprintf("  total: %d rules indexed\n\n", length(all_rules)))

cat("Building p21 lookup...\n")
p21_lookup  <- build_p21_lookup(all_rules)
cat(sprintf("  %d rule_ids with p21_id\n\n",
            sum(vapply(p21_lookup, nzchar, logical(1)))))

cat("Writing flat rule database...\n")
compile_rules_db(all_rules, p21_lookup)

cat("\nWriting slim configs...\n")
compile_configs()

cat("\nCompressing CT packages...\n")
compile_ct()

cat("\nCompressing p21 id map...\n")
compile_p21_map()

cat("\nCopying manifest...\n")
compile_manifest()

total_mb <- sum(file.info(list.files(file.path(repo_root, "inst", "rules"),
                                     recursive = TRUE,
                                     full.names = TRUE))$size) / 1024^2
cat(sprintf("\ninst/rules/ payload: %.2f MB\n", total_mb))
