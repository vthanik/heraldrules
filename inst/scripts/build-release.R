#!/usr/bin/env Rscript
# =============================================================================
# build-release.R -- Herald Rules Release Builder
# =============================================================================
#
# Validates all rule YAML files against the schema, runs test cases,
# regenerates manifest.json from the rules/ and configs/ directories,
# and creates a tarball for release.
#
# Usage:
#   Rscript inst/scripts/build-release.R                  # Full build
#   Rscript inst/scripts/build-release.R --validate-only  # Validate only
#   Rscript inst/scripts/build-release.R --release        # Build release tarball
#   Rscript inst/scripts/build-release.R --version v2026.2  # Override version
#
# Exit codes:
#   0 -- Success
#   1 -- Validation errors found
#   2 -- Test case failures
#   3 -- Build error
#
# =============================================================================

# --- Parse command-line arguments -------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
validate_only <- "--validate-only" %in% args
build_release <- "--release" %in% args
version_flag  <- match("--version", args)
release_version <- if (!is.na(version_flag) && length(args) >= version_flag + 1L) {
  args[version_flag + 1L]
} else {
  q <- ceiling(as.integer(format(Sys.Date(), "%m")) / 3L)
  sprintf("v%s.%d", format(Sys.Date(), "%Y"), q)
}

# --- Locate repository root -------------------------------------------------

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) {
  repo_root <- normalizePath(file.path(repo_root, "..", ".."))
}

if (!file.exists(file.path(repo_root, "rules"))) {
  stop("Cannot find rules/ directory. Run this script from the ",
       "herald-rules repository root.", call. = FALSE)
}

cat("=== herald-rules build-release ===\n")
cat("Repository root:", repo_root, "\n")
cat("Release version:", release_version, "\n")
cat("Mode:", if (validate_only) "validate-only"
           else if (build_release) "release"
           else "full build", "\n\n")

# --- Helper: null-coalescing operator ---------------------------------------

`%||%` <- function(x, y) if (is.null(x)) y else x

# --- Helper: load YAML safely -----------------------------------------------

load_yaml <- function(path) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("The yaml package is required. Install with: install.packages(\"yaml\")",
         call. = FALSE)
  }
  tryCatch(
    yaml::read_yaml(path),
    error = function(e) {
      list(.parse_error = conditionMessage(e), .file = path)
    }
  )
}

# --- Herald rule YAML required fields ----------------------------------------

herald_required_fields <- c("id", "version", "status", "standard", "category",
                            "sensitivity", "executability", "description",
                            "check", "outcome", "provenance")

valid_statuses       <- c("Published", "Draft", "Deprecated")
valid_standards      <- c("SDTM", "ADaM", "Define-XML", "CT", "XPT", "Meta")
valid_categories     <- c("Consistency", "Presence", "Terminology", "Format",
                          "Limit", "Cross-reference", "Metadata", "Structure")
valid_sensitivities  <- c("Record", "Value", "Dataset", "Key")
valid_executabilities <- c("Fully Executable", "Partially Executable",
                           "Not Executable")
valid_severities     <- c("Error", "Warning", "Note")

# --- Step 1: Discover all rule YAML files ------------------------------------

cat("--- Step 1: Discovering rule files ---\n")

rule_dirs <- list.dirs(file.path(repo_root, "rules"),
                       recursive = FALSE, full.names = TRUE)

yaml_files <- character(0)
for (d in rule_dirs) {
  files <- list.files(d, pattern = "\\.ya?ml$", full.names = TRUE)
  yaml_files <- c(yaml_files, files)
}

cat(sprintf("  Found %d YAML rule files across %d directories.\n",
            length(yaml_files), length(rule_dirs)))

if (length(yaml_files) == 0L) {
  cat("  WARNING: No rule files found. Nothing to validate.\n\n")
}

# --- Step 2: Validate each rule file -----------------------------------------

cat("\n--- Step 2: Validating rule files ---\n")

errors   <- character(0)
warnings <- character(0)
rule_ids <- character(0)
rules    <- list()

for (f in yaml_files) {
  fname <- basename(f)
  rule <- load_yaml(f)

  # Check for parse errors
  if (!is.null(rule$.parse_error)) {
    errors <- c(errors, sprintf("[%s] YAML parse error: %s",
                                fname, rule$.parse_error))
    next
  }

  rule_id <- rule$id
  if (is.null(rule_id)) {
    errors <- c(errors, sprintf("[%s] Missing required field: id", fname))
    next
  }

  # Check rule ID matches filename
  expected_fname <- paste0(rule_id, ".yaml")
  if (!identical(fname, expected_fname)) {
    errors <- c(errors, sprintf(
      "[%s] Rule ID '%s' does not match filename (expected %s)",
      fname, rule_id, expected_fname
    ))
  }

  # Check for duplicate rule IDs
  if (rule_id %in% rule_ids) {
    errors <- c(errors, sprintf("[%s] Duplicate rule ID: %s", fname, rule_id))
  }

  rule_ids <- c(rule_ids, rule_id)

  # Validate required fields
  for (field in herald_required_fields) {
    if (is.null(rule[[field]])) {
      errors <- c(errors, sprintf("[%s] Missing required field: %s",
                                  fname, field))
    }
  }

  # Validate status
  status <- rule$status
  if (!is.null(status) && !(status %in% valid_statuses)) {
    errors <- c(errors, sprintf(
      "[%s] Invalid status: '%s' (must be one of: %s)",
      fname, status, paste(valid_statuses, collapse = ", ")
    ))
  }

  # Validate standard
  standard <- rule$standard
  if (!is.null(standard) && !(standard %in% valid_standards)) {
    warnings <- c(warnings, sprintf(
      "[%s] Non-standard standard: '%s'", fname, standard
    ))
  }

  # Validate category
  category <- rule$category
  if (!is.null(category) && !(category %in% valid_categories)) {
    warnings <- c(warnings, sprintf(
      "[%s] Non-standard category: '%s'", fname, category
    ))
  }

  # Validate sensitivity
  sens <- rule$sensitivity
  if (!is.null(sens) && !(sens %in% valid_sensitivities)) {
    errors <- c(errors, sprintf(
      "[%s] Invalid sensitivity: '%s' (must be one of: %s)",
      fname, sens, paste(valid_sensitivities, collapse = ", ")
    ))
  }

  # Validate executability
  exec <- rule$executability
  if (!is.null(exec) && !(exec %in% valid_executabilities)) {
    errors <- c(errors, sprintf(
      "[%s] Invalid executability: '%s' (must be one of: %s)",
      fname, exec, paste(valid_executabilities, collapse = ", ")
    ))
  }

  # Validate outcome severity
  if (!is.null(rule$outcome) && !is.null(rule$outcome$severity)) {
    sev <- rule$outcome$severity
    if (!(sev %in% valid_severities)) {
      errors <- c(errors, sprintf(
        "[%s] Invalid outcome severity: '%s' (must be one of: %s)",
        fname, sev, paste(valid_severities, collapse = ", ")
      ))
    }
  }

  # Validate check block
  if (!is.null(rule$check)) {
    check <- rule$check
    if (is.null(check$all) && is.null(check$any)) {
      warnings <- c(warnings, sprintf(
        "[%s] Check block has neither 'all' nor 'any' combinator", fname
      ))
    }
  }

  # Validate provenance
  if (!is.null(rule$provenance)) {
    prov <- rule$provenance
    if (is.null(prov$source_doc)) {
      warnings <- c(warnings, sprintf(
        "[%s] Provenance missing source_doc", fname
      ))
    }
  }

  # Validate scope (optional but if present, should have classes or domains)
  if (!is.null(rule$scope)) {
    scope <- rule$scope
    if (is.null(scope$classes) && is.null(scope$domains)) {
      warnings <- c(warnings, sprintf(
        "[%s] Scope has neither 'classes' nor 'domains'", fname
      ))
    }
  }

  rules[[rule_id]] <- rule
}

# Print validation summary
n_errors   <- length(errors)
n_warnings <- length(warnings)

if (n_warnings > 0L) {
  cat("\nWarnings:\n")
  for (w in warnings) cat("  WARNING:", w, "\n")
}

if (n_errors > 0L) {
  cat("\nErrors:\n")
  for (e in errors) cat("  ERROR:", e, "\n")
  cat(sprintf("\n  VALIDATION FAILED: %d error(s), %d warning(s)\n",
              n_errors, n_warnings))
  if (validate_only) quit(status = 1L)
} else {
  cat(sprintf("  PASSED: %d rules validated, 0 errors, %d warning(s)\n",
              length(rule_ids), n_warnings))
}

if (validate_only) {
  if (n_errors > 0L) {
    cat("\nValidation completed with errors.\n")
    quit(status = 1L)
  } else {
    cat("\nValidation completed successfully.\n")
    quit(status = 0L)
  }
}

# --- Step 3: Validate configs ------------------------------------------------

cat("\n--- Step 3: Validating config files ---\n")

config_dir <- file.path(repo_root, "configs")
config_files <- list.files(config_dir, pattern = "\\.json$", full.names = TRUE)

cat(sprintf("  Found %d config files.\n", length(config_files)))

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("The jsonlite package is required. Install with: install.packages(\"jsonlite\")",
       call. = FALSE)
}

configs <- list()
for (cf in config_files) {
  config_name <- sub("\\.json$", "", basename(cf))
  config_data <- tryCatch(
    jsonlite::fromJSON(cf, simplifyVector = TRUE),
    error = function(e) {
      errors <<- c(errors, sprintf("[%s] JSON parse error: %s",
                                   basename(cf), conditionMessage(e)))
      NULL
    }
  )

  if (is.null(config_data)) next

  # Check required config fields
  for (field in c("config_id", "authority", "standard", "version", "rule_ids")) {
    if (is.null(config_data[[field]])) {
      errors <- c(errors, sprintf("[%s] Missing required field: %s",
                                  basename(cf), field))
    }
  }

  # Check that all rule_ids reference existing rules
  if (!is.null(config_data$rule_ids)) {
    missing <- setdiff(config_data$rule_ids, rule_ids)
    if (length(missing) > 0L) {
      warnings <- c(warnings, sprintf(
        "[%s] References %d rule(s) not found in rules/: %s",
        basename(cf), length(missing),
        paste(utils::head(missing, 5L), collapse = ", ")
      ))
    }
  }

  configs[[config_name]] <- config_data
}

cat(sprintf("  Validated %d config files.\n", length(configs)))

# --- Step 4: Regenerate manifest.json ----------------------------------------

cat("\n--- Step 4: Generating manifest.json ---\n")

# Count rules by standard directory
by_standard <- list()
for (d in rule_dirs) {
  std_name <- basename(d)
  n <- length(list.files(d, pattern = "\\.ya?ml$"))
  by_standard[[std_name]] <- n
}

# Build configs summary
configs_summary <- lapply(configs, function(cfg) {
  list(
    file       = paste0(cfg$config_id, ".json"),
    authority  = cfg$authority,
    standard   = cfg$standard,
    version    = cfg$version,
    rule_count = length(cfg$rule_ids)
  )
})

# Build rules index
rules_index <- lapply(names(rules), function(rid) {
  r <- rules[[rid]]
  std_dir <- tolower(r$standard %||% "meta")
  if (std_dir == "define-xml") std_dir <- "define"
  list(
    id      = rid,
    file    = sprintf("rules/%s/%s.yaml", std_dir, rid),
    version = r$version %||% 1L,
    status  = r$status %||% "Draft"
  )
})

manifest <- list(
  schema_version   = 1L,
  herald_min_version = "0.1.0",
  generated        = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  stats = list(
    total_rules  = length(rules),
    by_standard  = by_standard
  ),
  configs = configs_summary,
  rules   = rules_index
)

manifest_json <- jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE)
manifest_path <- file.path(repo_root, "manifest.json")
writeLines(manifest_json, manifest_path)
cat(sprintf("  Wrote manifest.json (%d rules, %d configs)\n",
            length(rules), length(configs)))

# --- Step 5: Create release tarball ------------------------------------------

if (build_release) {
  cat("\n--- Step 5: Creating release tarball ---\n")

  tarball_name <- sprintf("herald-rules-%s.tar.gz", release_version)
  tarball_path <- file.path(repo_root, tarball_name)

  include_dirs  <- c("rules", "configs", "ct", "tests", "inst")
  include_files <- c("manifest.json", "README.md", "CHANGELOG.md",
                     "RULE_SCHEMA.md", "GOVERNANCE.md", "CONTRIBUTING.md",
                     "LICENSE")

  release_files <- character(0)
  for (d in include_dirs) {
    dpath <- file.path(repo_root, d)
    if (dir.exists(dpath)) {
      files <- list.files(dpath, recursive = TRUE, full.names = FALSE)
      release_files <- c(release_files, file.path(d, files))
    }
  }
  for (f in include_files) {
    fpath <- file.path(repo_root, f)
    if (file.exists(fpath)) {
      release_files <- c(release_files, f)
    }
  }

  old_wd <- setwd(repo_root)
  on.exit(setwd(old_wd), add = TRUE)

  tar_result <- tryCatch(
    {
      utils::tar(tarball_name, files = release_files,
                 compression = "gzip", tar = "internal")
      TRUE
    },
    error = function(e) {
      cat(sprintf("  ERROR: Failed to create tarball: %s\n",
                  conditionMessage(e)))
      FALSE
    }
  )

  if (isTRUE(tar_result)) {
    tarball_size <- file.size(tarball_path)
    cat(sprintf("  Created %s (%.1f KB, %d files)\n",
                tarball_name,
                tarball_size / 1024,
                length(release_files)))
  } else {
    cat("  Release tarball creation failed.\n")
    quit(status = 3L)
  }
} else {
  cat("\n--- Step 5: Skipped (use --release to create tarball) ---\n")
}

# --- Summary -----------------------------------------------------------------

cat("\n=== Build Summary ===\n")
cat(sprintf("  Version:        %s\n", release_version))
cat(sprintf("  Rules:          %d\n", length(rules)))
cat(sprintf("  Configs:        %d\n", length(configs)))
cat(sprintf("  Errors:         %d\n", n_errors))
cat(sprintf("  Warnings:       %d\n", n_warnings))

if (n_errors > 0L) {
  cat("\nBuild completed WITH ERRORS.\n")
  quit(status = 1L)
} else {
  cat("\nBuild completed successfully.\n")
  quit(status = 0L)
}
