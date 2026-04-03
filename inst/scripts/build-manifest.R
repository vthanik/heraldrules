#!/usr/bin/env Rscript
# =============================================================================
# build-manifest.R -- Regenerate manifest.json from actual file counts
# =============================================================================

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) repo_root <- normalizePath(file.path(repo_root, "..", ".."))

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")

cat("=== Building Manifest ===\n\n")

# Count engine files
engines <- c("cdisc", "ct", "fda", "herald", "pmda")
by_engine <- list()
total_engine <- 0L
for (eng in engines) {
  d <- file.path(repo_root, "engines", eng)
  n <- length(list.files(d, pattern = "\\.yaml$"))
  by_engine[[eng]] <- n
  total_engine <- total_engine + n
  cat(sprintf("  engines/%s: %d\n", eng, n))
}

# Count configs
n_configs <- length(list.files(file.path(repo_root, "configs"), pattern = "\\.json$"))

# Build config summaries
config_summaries <- list()
config_files <- list.files(file.path(repo_root, "configs"), pattern = "\\.json$", full.names = TRUE)
for (f in config_files) {
  cfg <- jsonlite::fromJSON(readLines(f, warn = FALSE), simplifyVector = FALSE)
  config_summaries[[length(config_summaries) + 1L]] <- list(
    file = basename(f),
    authority = cfg$authority %||% "",
    standard = cfg$standard %||% "",
    version = cfg$version %||% "",
    rule_count = length(cfg$rule_ids %||% list())
  )
}

manifest <- list(
  schema_version = 2L,
  herald_min_version = "0.1.0",
  generated = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  sources = list(
    cdisc = "CDISC Library API (library.cdisc.org)",
    fda = "FDA Validator Rules v1.6 (December 2022) + Business Rules v1.5",
    pmda = "PMDA Validation Rules v6.0 (March 2025)",
    ct = "NCI EVS CDISC Controlled Terminology (2025-09-26)",
    herald = "Herald-original rules (gap-fill for P21 parity)"
  ),
  stats = list(
    total_engine_rules = total_engine,
    by_engine = by_engine,
    configs = n_configs
  ),
  configs = config_summaries
)

out <- file.path(repo_root, "manifest.json")
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), out)
cat(sprintf("\nTotal: %d engine rules, %d configs\n", total_engine, n_configs))
cat(sprintf("Written: %s\n", out))
