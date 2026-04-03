#!/usr/bin/env Rscript
# =============================================================================
# fetch-ct.R -- Fetch CDISC Controlled Terminology from NCI EVS
# =============================================================================
#
# Downloads the latest CDISC Controlled Terminology packages from NCI EVS
# and converts them to herald's ct/*.json format.
#
# Usage:
#   Rscript inst/scripts/fetch-ct.R               # Fetch all CT packages
#   Rscript inst/scripts/fetch-ct.R --sdtm-only   # SDTM CT only
#   Rscript inst/scripts/fetch-ct.R --adam-only    # ADaM CT only
#
# Output:
#   ct/sdtm-ct.json  -- SDTM codelist terms + extensibility
#   ct/adam-ct.json   -- ADaM codelist terms + extensibility
#   ct/ct-manifest.json -- CT version metadata
#
# Requirements:
#   - Internet access to api-evsrest.nci.nih.gov
#   - jsonlite package
#
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
sdtm_only <- "--sdtm-only" %in% args
adam_only  <- "--adam-only" %in% args

# --- Locate repository root -------------------------------------------------

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) {
  repo_root <- normalizePath(file.path(repo_root, "..", ".."))
}

ct_dir <- file.path(repo_root, "ct")
if (!dir.exists(ct_dir)) {
  dir.create(ct_dir, recursive = TRUE)
}

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("The jsonlite package is required.", call. = FALSE)
}

cat("=== Herald CT Fetch ===\n\n")

# --- NCI EVS API configuration -----------------------------------------------

EVS_BASE <- "https://api-evsrest.nci.nih.gov/api/v1"

# CDISC terminology subset codes in NCI Thesaurus
CT_PACKAGES <- list(
  sdtm = list(
    name    = "CDISC SDTM Controlled Terminology",
    code    = "C66830",
    output  = "sdtm-ct.json"
  ),
  adam = list(
    name    = "CDISC ADaM Controlled Terminology",
    code    = "C81222",
    output  = "adam-ct.json"
  )
)

# --- Helper: fetch JSON from URL ---------------------------------------------

fetch_json <- function(url) {
  tryCatch(
    {
      resp <- readLines(url(url), warn = FALSE)
      jsonlite::fromJSON(paste(resp, collapse = "\n"),
                         simplifyVector = FALSE)
    },
    error = function(e) {
      cat(sprintf("  ERROR: Failed to fetch %s\n    %s\n",
                  url, conditionMessage(e)))
      NULL
    }
  )
}

# --- Helper: fetch codelist details ------------------------------------------

fetch_codelist <- function(code) {
  url <- sprintf("%s/concept/ncit/%s?include=children,properties",
                 EVS_BASE, code)
  fetch_json(url)
}

# --- Process each CT package -------------------------------------------------

packages_to_fetch <- if (sdtm_only) {
  CT_PACKAGES["sdtm"]
} else if (adam_only) {
  CT_PACKAGES["adam"]
} else {
  CT_PACKAGES
}

ct_versions <- list()

for (pkg_name in names(packages_to_fetch)) {
  pkg <- packages_to_fetch[[pkg_name]]
  cat(sprintf("Fetching %s...\n", pkg$name))

  # Fetch the top-level terminology concept to get subsets
  top <- fetch_codelist(pkg$code)

  if (is.null(top)) {
    cat(sprintf("  Skipping %s (fetch failed)\n\n", pkg_name))
    next
  }

  # Extract codelist subsets from children
  codelists <- list()

  if (!is.null(top$children)) {
    cat(sprintf("  Found %d codelist subsets\n", length(top$children)))

    for (child in top$children) {
      cl_code <- child$code
      cl_name <- child$name

      # Fetch detailed codelist with its terms
      cl_detail <- fetch_codelist(cl_code)
      if (is.null(cl_detail)) next

      # Extract terms from children
      terms <- character(0)
      if (!is.null(cl_detail$children)) {
        terms <- vapply(cl_detail$children, function(t) {
          t$name %||% ""
        }, character(1))
        terms <- terms[nzchar(terms)]
      }

      # Check extensibility from properties
      extensible <- FALSE
      if (!is.null(cl_detail$properties)) {
        for (prop in cl_detail$properties) {
          if (identical(prop$type, "Extensible_List") &&
              identical(prop$value, "Yes")) {
            extensible <- TRUE
            break
          }
        }
      }

      codelists[[cl_name]] <- list(
        code        = cl_code,
        name        = cl_name,
        extensible  = extensible,
        terms       = terms
      )
    }
  } else {
    cat("  No children found. Using cached version if available.\n")
  }

  # Write output JSON
  output_path <- file.path(ct_dir, pkg$output)

  if (length(codelists) > 0L) {
    json_out <- jsonlite::toJSON(codelists, auto_unbox = TRUE, pretty = TRUE)
    writeLines(json_out, output_path)
    cat(sprintf("  Wrote %s (%d codelists)\n\n", pkg$output, length(codelists)))
  } else {
    cat(sprintf("  WARNING: No codelists extracted for %s\n\n", pkg_name))
  }

  ct_versions[[pkg_name]] <- list(
    package     = pkg$name,
    source      = "NCI EVS (api-evsrest.nci.nih.gov)",
    fetched     = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    n_codelists = length(codelists),
    n_terms     = sum(vapply(codelists, function(cl) length(cl$terms), integer(1)))
  )
}

# --- Write ct-manifest.json --------------------------------------------------

manifest <- list(
  version  = format(Sys.Date(), "%Y-%m-%d"),
  source   = "NCI EVS CDISC Controlled Terminology",
  fetched  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  packages = ct_versions
)

manifest_path <- file.path(ct_dir, "ct-manifest.json")
manifest_json <- jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE)
writeLines(manifest_json, manifest_path)
cat(sprintf("Wrote ct-manifest.json (version: %s)\n", manifest$version))

cat("\nDone.\n")
