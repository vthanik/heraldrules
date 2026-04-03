#!/usr/bin/env Rscript
# =============================================================================
# check-updates.R -- Herald Source Update Checker
# =============================================================================
#
# Checks each canonical source URL for version changes.
# Compares against current_version in inst/sources.json.
# Prints a report of what's new and what action is needed.
#
# Usage:
#   Rscript inst/scripts/check-updates.R          # Check all sources
#   Rscript inst/scripts/check-updates.R --update  # Update sources.json
#
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
do_update <- "--update" %in% args

# --- Locate repository root -------------------------------------------------

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) {
  repo_root <- normalizePath(file.path(repo_root, "..", ".."))
}

sources_path <- file.path(repo_root, "inst", "sources.json")
if (!file.exists(sources_path)) {
  stop("Cannot find inst/sources.json. Run from herald-rules repo root.",
       call. = FALSE)
}

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("The jsonlite package is required.", call. = FALSE)
}

sources <- jsonlite::fromJSON(sources_path, simplifyVector = FALSE)

cat(sprintf("=== Herald Source Update Check (%s) ===\n\n",
            format(Sys.Date(), "%Y-%m-%d")))

# --- Helper: safe HTTP GET ---------------------------------------------------

safe_get <- function(url) {
  tryCatch(
    {
      con <- url(url, open = "r")
      on.exit(close(con), add = TRUE)
      paste(readLines(con, warn = FALSE), collapse = "\n")
    },
    error = function(e) {
      NULL
    }
  )
}

# --- Check each source -------------------------------------------------------

results <- list()

for (src in sources$sources) {
  src_id   <- src$id
  src_name <- src$name
  cur_ver  <- src$current_version
  cur_date <- src$current_date

  cat(sprintf("  %-25s", paste0(src_name, ":")))

  new_ver <- NULL
  action  <- NULL

  # Source-specific version checks
  if (src_id == "cdisc-ct") {
    # Check NCI EVS API for latest CT package date
    api_url <- src$api_url
    if (!is.null(api_url)) {
      # NCI EVS API: check for CDISC SDTM terminology
      resp <- safe_get(paste0(api_url, "?include=minimal&list=CDISC+SDTM+Terminology"))
      if (!is.null(resp)) {
        # Try to extract version date from response
        data <- tryCatch(jsonlite::fromJSON(resp, simplifyVector = FALSE),
                         error = function(e) NULL)
        if (!is.null(data) && !is.null(data$version)) {
          new_ver <- data$version
        }
      }
    }
  } else if (src_id == "cdisc-open-rules") {
    # Check GitHub API for latest release
    api_url <- src$api_url
    if (!is.null(api_url)) {
      resp <- safe_get(api_url)
      if (!is.null(resp)) {
        data <- tryCatch(jsonlite::fromJSON(resp, simplifyVector = FALSE),
                         error = function(e) NULL)
        if (!is.null(data) && !is.null(data$tag_name)) {
          new_ver <- data$tag_name
        }
      }
    }
  }

  # Report
  if (!is.null(new_ver) && !identical(new_ver, cur_ver)) {
    cat(sprintf("UPDATED: %s -> %s\n", cur_ver, new_ver))
    action <- sprintf("Review changes and update herald rules accordingly")

    if (src_id == "cdisc-ct") {
      action <- "Run inst/scripts/fetch-ct.R to update ct/*.json"
    }

    cat(sprintf("    Action: %s\n", action))

    if (do_update) {
      src$current_version <- new_ver
      src$current_date <- format(Sys.Date(), "%Y-%m-%d")
    }
  } else {
    ver_str <- if (!is.null(cur_date)) {
      sprintf("%s (%s)", cur_ver, cur_date)
    } else {
      cur_ver
    }
    cat(sprintf("%s -> No change\n", ver_str))
  }

  results[[src_id]] <- list(
    name        = src_name,
    current     = cur_ver,
    new         = new_ver,
    changed     = !is.null(new_ver) && !identical(new_ver, cur_ver),
    action      = action
  )
}

# --- Update sources.json if --update flag is set -----------------------------

if (do_update) {
  any_changes <- any(vapply(results, function(r) isTRUE(r$changed), logical(1)))
  if (any_changes) {
    json_out <- jsonlite::toJSON(sources, auto_unbox = TRUE, pretty = TRUE)
    writeLines(json_out, sources_path)
    cat("\n  Updated inst/sources.json with new versions.\n")
  } else {
    cat("\n  No changes detected. inst/sources.json unchanged.\n")
  }
}

# --- Summary -----------------------------------------------------------------

n_changed <- sum(vapply(results, function(r) isTRUE(r$changed), logical(1)))
cat(sprintf("\n  %d of %d sources have updates available.\n",
            n_changed, length(results)))

if (n_changed > 0L) {
  cat("\n  Actions needed:\n")
  for (r in results) {
    if (isTRUE(r$changed)) {
      cat(sprintf("    - %s: %s\n", r$name, r$action))
    }
  }
}

cat("\nDone.\n")
