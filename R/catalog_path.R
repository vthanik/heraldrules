#' Path to a compiled heraldrules config
#'
#' Returns the on-disk path to the pre-compiled, gzipped JSON config for
#' a given submission profile (FDA / PMDA / Combined x standard x version).
#' The `herald` R package calls this to load a rule catalog at validate
#' time without ever touching the loose YAML authoring source.
#'
#' Each config file carries only the list of `rule_ids` that belong to
#' it. Full rule definitions live in the flat database at
#' [rules_db_path()] and are filtered by the id list.
#'
#' @param config_id One of the config identifiers returned by
#'   [available_configs()]. Examples: `"fda-sdtm-ig-3.3"`,
#'   `"pmda-adam-ig-1.1"`, `"all-sdtm-ig-3.3"`, `"herald"`.
#'
#' @return Character scalar. An absolute path to the `.json.gz` file.
#'
#' @seealso [load_catalog()] to load filtered rule records in one call,
#'   [available_configs()] to discover valid `config_id` values.
#' @export
#' @examples
#' catalog_path("fda-sdtm-ig-3.3")
catalog_path <- function(config_id) {
  stopifnot(is.character(config_id), length(config_id) == 1L, nzchar(config_id))
  path <- system.file("rules", "configs", paste0(config_id, ".json.gz"),
                      package = "heraldrules")
  if (!nzchar(path)) {
    stop(sprintf("No compiled catalog for config_id %s. Use available_configs() to list valid ids.",
                 shQuote(config_id)), call. = FALSE)
  }
  path
}

#' Path to the flat rule database
#'
#' One gzipped JSON holding every rule record exactly once. Rules appear
#' in multiple configs via id reference; this file is the source of
#' truth for rule definitions.
#'
#' @return Character scalar. Absolute path to `rules.json.gz`.
#' @export
rules_db_path <- function() {
  path <- system.file("rules", "rules.json.gz", package = "heraldrules")
  if (!nzchar(path)) {
    stop("rules.json.gz not bundled; reinstall heraldrules.", call. = FALSE)
  }
  path
}

#' Load a config's rule records
#'
#' Reads the slim config (list of `rule_ids`), then filters the flat rule
#' database to the matching records. The database load is memoised within
#' a session so repeated calls are fast.
#'
#' @inheritParams catalog_path
#' @return List of rule definitions.
#' @seealso [catalog_path()], [rules_db_path()].
#' @export
#' @examples
#' rules <- load_catalog("fda-sdtm-ig-3.3")
#' length(rules)
load_catalog <- function(config_id) {
  cfg <- jsonlite::fromJSON(gzfile(catalog_path(config_id)),
                            simplifyVector = FALSE)
  ids <- unlist(cfg$rule_ids)
  db  <- .rules_db()
  hit <- db[ids]
  hit[!vapply(hit, is.null, logical(1L))]
}

# Memoised read of rules.json.gz within a session
.rules_db_cache <- new.env(parent = emptyenv())
.rules_db <- function() {
  if (!is.null(.rules_db_cache$db)) return(.rules_db_cache$db)
  db <- jsonlite::fromJSON(gzfile(rules_db_path()), simplifyVector = FALSE)
  .rules_db_cache$db <- db
  db
}

#' List available config identifiers
#'
#' @return Character vector of config ids (basenames with `.json.gz`
#'   stripped).
#' @export
available_configs <- function() {
  dir <- system.file("rules", "configs", package = "heraldrules")
  if (!nzchar(dir)) return(character())
  files <- list.files(dir, pattern = "\\.json\\.gz$")
  sub("\\.json\\.gz$", "", files)
}

#' Load bundled CDISC Controlled Terminology
#'
#' Returns the decompressed CT terms for one submission standard.
#' `herald` merges these on top of any sponsor-supplied CT via
#' `register_ct()`.
#'
#' @param package One of `"sdtm"` or `"adam"`.
#' @return Data frame of CT terms.
#' @export
load_ct <- function(package = c("sdtm", "adam")) {
  package <- match.arg(package)
  path <- system.file("rules", "ct",
                      paste0(package, "-ct.rds"),
                      package = "heraldrules")
  if (!nzchar(path)) {
    stop(sprintf("No bundled CT package %s.", shQuote(package)), call. = FALSE)
  }
  readRDS(path)
}

#' P21 Community rule-id translation map
#'
#' Returns a two-column data frame mapping every herald rule_id to its
#' P21 Community display id (where one exists). Used by the herald R
#' package to surface P21 ids in reports as the primary column.
#'
#' @return Data frame with columns `rule_id`, `p21_id`. Rows with no
#'   P21 equivalent carry an empty `p21_id`.
#' @export
p21_id_map <- function() {
  path <- system.file("rules", "p21-id-map.csv.gz",
                      package = "heraldrules")
  if (!nzchar(path)) {
    stop("p21-id-map.csv.gz not bundled; reinstall heraldrules.", call. = FALSE)
  }
  utils::read.csv(gzfile(path), stringsAsFactors = FALSE)
}
