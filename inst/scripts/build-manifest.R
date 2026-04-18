#!/usr/bin/env Rscript
# =============================================================================
# build-manifest.R -- Regenerate manifest.json from actual file counts
# =============================================================================

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) repo_root <- normalizePath(file.path(repo_root, "..", ".."))

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite required")
if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml required")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x

cat("=== Building Manifest ===\n\n")

RUNNABLE_STATES <- c("Fully Executable", "Hardcoded",
                     "Partially Executable",
                     "Partially Executable - Possible Overreporting",
                     "Partially Executable - Possible Underreporting")

is_runnable <- function(f) {
  r <- tryCatch(yaml::read_yaml(f), error = function(e) NULL)
  if (is.null(r)) return(FALSE)
  exec <- r$executability %||% r$Executability %||% ""
  exec %in% RUNNABLE_STATES
}

# Count engine files, and of those, how many are runnable.
engines <- c("cdisc", "ct", "fda", "herald", "pmda")
by_engine <- list()
executable_by_engine <- list()
total_engine <- 0L
total_executable <- 0L
for (eng in engines) {
  d <- file.path(repo_root, "engines", eng)
  files <- list.files(d, pattern = "\\.yaml$", recursive = TRUE, full.names = TRUE)
  n <- length(files)
  nexec <- sum(vapply(files, is_runnable, logical(1)))
  by_engine[[eng]] <- n
  executable_by_engine[[eng]] <- nexec
  total_engine <- total_engine + n
  total_executable <- total_executable + nexec
  cat(sprintf("  engines/%s: %d total, %d runnable\n", eng, n, nexec))
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
    executable_engine_rules = total_executable,
    by_engine = by_engine,
    executable_by_engine = executable_by_engine,
    configs = n_configs
  ),
  configs = config_summaries
)

out <- file.path(repo_root, "manifest.json")
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), out)
cat(sprintf("\nTotal: %d engine rules (%d runnable, %d reference), %d configs\n",
            total_engine, total_executable, total_engine - total_executable, n_configs))
cat(sprintf("Written: %s\n", out))
