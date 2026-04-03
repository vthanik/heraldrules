#!/usr/bin/env Rscript
# =============================================================================
# convert-p21-to-herald.R -- Convert Pinnacle 21 Rules to Herald YAML Format
# =============================================================================
#
# Reads P21 rule YAML files from .local/p21-new/ and converts them to
# herald's HRL-* format in rules/.
#
# Features:
#   - Deduplicates across P21 versions (prefers latest IG)
#   - Skips already-converted rules (checks existing provenance)
#   - Skips SEND (SE) rules
#   - Handles all P21 types: Required, Match, Regex, Unique, Condition,
#     Find, Lookup, Schematron, Property, Metadata
#   - Extracts CG/FDA IDs from Authorities section
#   - Infers scope from variable names and IG context
#
# Usage:
#   Rscript inst/scripts/convert-p21-to-herald.R                   # All rules
#   Rscript inst/scripts/convert-p21-to-herald.R --standard sdtm   # SDTM only
#   Rscript inst/scripts/convert-p21-to-herald.R --dry-run          # Preview
#   Rscript inst/scripts/convert-p21-to-herald.R --limit 50         # First 50
#
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
dry_run      <- "--dry-run" %in% args
standard_idx <- match("--standard", args)
limit_idx    <- match("--limit", args)

target_standard <- if (!is.na(standard_idx) && length(args) >= standard_idx + 1L) {
  args[standard_idx + 1L]
} else {
  NULL
}

rule_limit <- if (!is.na(limit_idx) && length(args) >= limit_idx + 1L) {
  as.integer(args[limit_idx + 1L])
} else {
  Inf
}

# --- Locate repository root -------------------------------------------------

repo_root <- getwd()
if (grepl("inst/scripts$", repo_root)) {
  repo_root <- normalizePath(file.path(repo_root, "..", ".."))
}

if (!requireNamespace("yaml", quietly = TRUE)) {
  stop("The yaml package is required.", call. = FALSE)
}

cat("=== P21 to Herald Rule Converter ===\n\n")

# --- P21 source directories --------------------------------------------------

p21_dir <- file.path(repo_root, ".local", "p21-new")
if (!dir.exists(p21_dir)) {
  stop("P21 source directory not found: ", p21_dir,
       "\nPlace P21 rule YAML exports in .local/p21-new/",
       call. = FALSE)
}

# --- Utility ------------------------------------------------------------------

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

# --- Standard mappings --------------------------------------------------------

p21_to_herald_std <- list(
  SD = list(std = "SDTM",       prefix = "HRL-SD", dir = "sdtm"),
  AD = list(std = "ADaM",       prefix = "HRL-AD", dir = "adam"),
  DD = list(std = "Define-XML", prefix = "HRL-DD", dir = "define"),
  CT = list(std = "CT",         prefix = "HRL-CT", dir = "ct"),
  XP = list(std = "XPT",        prefix = "HRL-XP", dir = "xpt"),
  OD = list(std = "Define-XML", prefix = "HRL-DD", dir = "define")
)

# IG directory preference (higher = preferred for dedup)
ig_priority <- c(
  "sdtm-ig-3.3"     = 100L,
  "sdtm-ig-3.2"     = 90L,
  "sdtm-ig-3.1.3"   = 80L,
  "sdtm-ig-3.1.2"   = 70L,
  "adam-ig-1.1"      = 100L,
  "adam-ig-1.0"      = 90L,
  "define-xml"       = 100L,
  "send-ig-dart-1.1" = 10L,
  "send-ig-ar-1.0"  = 10L,
  "send-ig-3.1.1"   = 10L,
  "send-ig-3.1"     = 10L,
  "send-ig-3.0"     = 10L
)

# --- Discover already-converted P21 IDs --------------------------------------

cat("Checking existing rules...\n")

existing_p21_ids <- character(0)
for (std_dir in c("sdtm", "adam", "define", "ct", "xpt")) {
  rules_path <- file.path(repo_root, "rules", std_dir)
  if (!dir.exists(rules_path)) next
  rule_files <- list.files(rules_path, pattern = "\\.yaml$", full.names = TRUE)
  for (rf in rule_files) {
    content <- tryCatch(yaml::read_yaml(rf), error = function(e) NULL)
    if (!is.null(content) && !is.null(content$provenance$p21_id)) {
      existing_p21_ids <- c(existing_p21_ids, content$provenance$p21_id)
    }
  }
}

cat(sprintf("  Found %d already-converted P21 IDs\n", length(existing_p21_ids)))

# --- Find next available ID for each standard ---------------------------------

get_next_id <- function(std_dir) {
  rules_path <- file.path(repo_root, "rules", std_dir)
  if (!dir.exists(rules_path)) {
    dir.create(rules_path, recursive = TRUE)
    return(1L)
  }
  existing <- list.files(rules_path, pattern = "\\.yaml$")
  if (length(existing) == 0L) return(1L)
  nums <- as.integer(sub(".*-(\\d{4})\\.yaml$", "\\1", existing))
  nums <- nums[!is.na(nums)]
  if (length(nums) == 0L) return(1L)
  max(nums) + 1L
}

counters <- list(
  SD = get_next_id("sdtm"),
  AD = get_next_id("adam"),
  DD = get_next_id("define"),
  CT = get_next_id("ct"),
  XP = get_next_id("xpt"),
  OD = get_next_id("define")  # OD merges into define
)

# --- P21 operator mapping ----------------------------------------------------

p21_operator_map <- list(
  "equal_to"                     = "equal_to",
  "not_equal_to"                 = "not_equal_to",
  "less_than"                    = "less_than",
  "less_than_or_equal_to"        = "less_than_or_equal_to",
  "greater_than"                 = "greater_than",
  "greater_than_or_equal_to"     = "greater_than_or_equal_to",
  "empty"                        = "is_empty",
  "non_empty"                    = "non_empty",
  "is_unique"                    = "is_unique",
  "not_unique"                   = "not_unique",
  "in"                           = "in",
  "not_in"                       = "not_in",
  "matches_regex"                = "matches_regex",
  "not_matches_regex"            = "not_matches_regex",
  "starts_with"                  = "starts_with",
  "ends_with"                    = "ends_with",
  "contains"                     = "contains",
  "max_length"                   = "max_length",
  "min_length"                   = "min_length",
  "is_integer"                   = "is_integer",
  "is_numeric"                   = "is_numeric",
  "is_valid_iso8601"             = "is_valid_iso8601",
  "is_valid_duration"            = "is_valid_duration",
  "is_ordered_set"               = "is_ordered_set",
  "all_values_equal"             = "all_values_equal",
  "is_not_unique_set"            = "is_not_unique_set",
  "distinct"                     = "distinct",
  "is_uppercase"                 = "is_uppercase",
  "is_lowercase"                 = "is_lowercase"
)

# Expression operator mapping (used in @and/@or expressions)
expr_operator_map <- list(
  "=="     = "equal_to",
  "!="     = "not_equal_to",
  "@lt"    = "less_than",
  "@lteq"  = "less_than_or_equal_to",
  "@gt"    = "greater_than",
  "@gteq"  = "greater_than_or_equal_to",
  "@eqic"  = "equal_to_case_insensitive",
  "@in"    = "in",
  "@notin" = "not_in"
)

# --- P21 category mapping ----------------------------------------------------

p21_category_map <- list(
  "Consistency Check"      = "Consistency",
  "Consistency"            = "Consistency",
  "Variable Presence"      = "Presence",
  "Value Presence"         = "Presence",
  "Presence"               = "Presence",
  "Controlled Terminology" = "Terminology",
  "Terminology"            = "Terminology",
  "Format Check"           = "Format",
  "Format"                 = "Format",
  "Limit Check"            = "Limit",
  "Limit"                  = "Limit",
  "Cross-Domain"           = "Cross-reference",
  "Cross-reference"        = "Cross-reference",
  "Metadata Check"         = "Metadata",
  "Metadata"               = "Metadata",
  "Record Data"            = "Consistency",
  "Define Metadata"        = "Metadata",
  "Dataset Metadata"       = "Metadata"
)

# --- P21 sensitivity mapping -------------------------------------------------

p21_sensitivity_map <- list(
  "Record"  = "Record",
  "Dataset" = "Dataset",
  "Study"   = "Dataset",
  "Value"   = "Record"
)

# =============================================================================
# P21 Expression Parser
# =============================================================================
# Parses P21 expression strings like:
#   "AESER == 'Y'"
#   "RDOMAIN != ''"
#   "%Domain%STDY @lteq %Domain%ENDY"
#   "A == 'X' @or B == 'Y'"
#   "A != '' @and B != ''"

parse_single_expression <- function(expr) {
  expr <- trimws(expr)
  if (nchar(expr) == 0L) return(NULL)

  # Clean up template markers for variable names
  clean_var <- function(v) {
    v <- trimws(v)
    # %Domain%VAR -> --VAR (domain prefix placeholder)
    v <- gsub("%Domain%", "--", v)
    # %Variable% -> VARIABLE (generic)
    v <- gsub("%Variable%", "VARIABLE", v)
    # %Variable.1% -> VARIABLE
    v <- gsub("%Variable\\.\\d+%", "VARIABLE", v)
    v
  }

  clean_value <- function(v) {
    v <- trimws(v)
    # Remove surrounding quotes
    v <- gsub("^'(.*)'$", "\\1", v)
    v <- gsub('^"(.*)"$', "\\1", v)
    v
  }

  # Try each expression operator
  for (op_str in names(expr_operator_map)) {
    # For symbol operators (==, !=), use word boundary-free split
    # For @ operators, they're already word-like
    if (grepl(op_str, expr, fixed = TRUE)) {
      parts <- strsplit(expr, op_str, fixed = TRUE)[[1L]]
      if (length(parts) == 2L) {
        var_name <- clean_var(parts[1L])
        raw_val  <- clean_value(parts[2L])

        herald_op <- expr_operator_map[[op_str]]

        # Empty string check: VAR != '' -> non_empty; VAR == '' -> is_empty
        if (raw_val == "" || raw_val == "''") {
          if (herald_op == "not_equal_to") {
            return(list(name = var_name, operator = "non_empty"))
          } else if (herald_op == "equal_to") {
            return(list(name = var_name, operator = "is_empty"))
          }
        }

        # Variable-to-variable comparison: value starts with -- or %
        if (grepl("^(--|%)", raw_val)) {
          raw_val <- clean_var(raw_val)
          herald_op <- paste0(herald_op, "_variable")
          return(list(name = var_name, operator = herald_op, value = raw_val))
        }

        result <- list(name = var_name, operator = herald_op)
        if (nchar(raw_val) > 0L) result$value <- raw_val
        return(result)
      }
    }
  }

  # Fallback: can't parse
  NULL
}

parse_compound_expression <- function(expr) {
  expr <- trimws(expr)
  if (nchar(expr) == 0L) return(NULL)

  # Split on @or first (lower precedence)
  if (grepl(" @or ", expr, fixed = TRUE)) {
    parts <- strsplit(expr, " @or ", fixed = TRUE)[[1L]]
    conditions <- lapply(parts, parse_single_expression)
    conditions <- conditions[!vapply(conditions, is.null, logical(1))]
    if (length(conditions) > 0L) {
      return(list(combinator = "any", conditions = conditions))
    }
  }

  # Split on @and
  if (grepl(" @and ", expr, fixed = TRUE)) {
    parts <- strsplit(expr, " @and ", fixed = TRUE)[[1L]]
    conditions <- lapply(parts, parse_single_expression)
    conditions <- conditions[!vapply(conditions, is.null, logical(1))]
    if (length(conditions) > 0L) {
      return(list(combinator = "all", conditions = conditions))
    }
  }

  # Single expression
  single <- parse_single_expression(expr)
  if (!is.null(single)) {
    return(list(combinator = "all", conditions = list(single)))
  }

  NULL
}

# =============================================================================
# Check Conversion (P21 Check → Herald Check)
# =============================================================================

convert_check <- function(p21_check, p21_type) {
  if (is.null(p21_check)) return(list(all = list()))

  p21_type <- p21_type %||% "Unknown"

  # --- Schematron: not executable ---
  if (identical(p21_type, "Schematron") ||
      identical(p21_check$type, "schematron")) {
    return(list(all = list()))
  }

  # --- Property: not executable in herald ---
  if (identical(p21_type, "Property") ||
      identical(p21_check$type, "property")) {
    return(list(all = list()))
  }

  # --- Metadata: cross-reference check ---
  if (identical(p21_type, "Metadata") ||
      identical(p21_check$type, "metadata")) {
    return(list(all = list()))
  }

  # --- Lookup: external terminology check ---
  if (identical(p21_type, "Lookup") ||
      identical(p21_check$type, "lookup")) {
    # Try to extract the when condition at least
    when_expr <- p21_check$`when`
    if (!is.null(when_expr) && is.character(when_expr)) {
      parsed <- parse_compound_expression(when_expr)
      if (!is.null(parsed)) {
        return(list(all = parsed$conditions))
      }
    }
    return(list(all = list()))
  }

  # --- Find: dataset/variable existence ---
  if (identical(p21_type, "Find") ||
      identical(p21_check$type, "find")) {
    terms <- p21_check$terms %||% p21_check$value
    target <- p21_check$target %||% "Dataset"
    if (!is.null(terms)) {
      op <- if (identical(target, "Metadata") ||
                !is.null(p21_check$variable)) "variable_exists" else "dataset_exists"
      return(list(all = list(list(
        name = p21_check$variable %||% "DOMAIN",
        operator = op,
        value = terms
      ))))
    }
    return(list(all = list()))
  }

  # --- Simple single-condition (name/operator/value at top level) ---
  if (!is.null(p21_check$name) && !is.null(p21_check$operator)) {
    p21_op <- p21_check$operator
    herald_op <- p21_operator_map[[p21_op]] %||% p21_op

    cond <- list(name = p21_check$name, operator = herald_op)
    if (!is.null(p21_check$value)) cond$value <- p21_check$value
    if (!is.null(p21_check$group_by)) cond$group_by <- p21_check$group_by
    return(list(all = list(cond)))
  }

  # --- Condition type: all/test/when structure ---
  if (!is.null(p21_check$all) && is.list(p21_check$all)) {
    conditions <- list()

    # Separate test and when clauses
    test_expr <- NULL
    when_expr <- NULL
    direct_conditions <- list()

    for (item in p21_check$all) {
      if (is.list(item)) {
        if (!is.null(item$test)) {
          test_expr <- item$test
        } else if (!is.null(item$`when`)) {
          when_expr <- item$`when`
        } else if (!is.null(item$name) && !is.null(item$operator)) {
          # Direct condition with name/operator
          p21_op <- item$operator
          herald_op <- p21_operator_map[[p21_op]] %||% p21_op
          cond <- list(name = item$name, operator = herald_op)
          if (!is.null(item$value)) cond$value <- item$value
          if (!is.null(item$group_by)) cond$group_by <- item$group_by
          direct_conditions <- c(direct_conditions, list(cond))
        }
      } else if (is.character(item)) {
        # Could be a standalone expression
        parsed <- parse_compound_expression(item)
        if (!is.null(parsed)) {
          direct_conditions <- c(direct_conditions, parsed$conditions)
        }
      }
    }

    # Parse the test expression
    if (!is.null(test_expr) && is.character(test_expr)) {
      parsed_test <- parse_compound_expression(test_expr)
      if (!is.null(parsed_test)) {
        if (parsed_test$combinator == "any") {
          # test has OR logic -> wrap in any
          conditions <- c(conditions, list(list(any = parsed_test$conditions)))
        } else {
          conditions <- c(conditions, parsed_test$conditions)
        }
      }
    }

    # Parse the when expression (acts as a precondition/filter)
    if (!is.null(when_expr) && is.character(when_expr)) {
      parsed_when <- parse_compound_expression(when_expr)
      if (!is.null(parsed_when)) {
        conditions <- c(conditions, parsed_when$conditions)
      }
    }

    # Add any direct conditions
    conditions <- c(conditions, direct_conditions)

    if (length(conditions) > 0L) {
      return(list(all = conditions))
    }
  }

  # --- @and/@or at top level ---
  if (!is.null(p21_check$`@and`)) {
    conditions <- list()
    for (item in p21_check$`@and`) {
      if (is.list(item) && !is.null(item$name)) {
        p21_op <- item$operator %||% item$type
        herald_op <- p21_operator_map[[p21_op]] %||% p21_op
        cond <- list(name = item$name, operator = herald_op)
        if (!is.null(item$value)) cond$value <- item$value
        conditions <- c(conditions, list(cond))
      }
    }
    return(list(all = conditions))
  }

  if (!is.null(p21_check$`@or`)) {
    conditions <- list()
    for (item in p21_check$`@or`) {
      if (is.list(item) && !is.null(item$name)) {
        p21_op <- item$operator %||% item$type
        herald_op <- p21_operator_map[[p21_op]] %||% p21_op
        cond <- list(name = item$name, operator = herald_op)
        if (!is.null(item$value)) cond$value <- item$value
        conditions <- c(conditions, list(cond))
      }
    }
    return(list(any = conditions))
  }

  # --- Single condition at top level (with $conditions list) ---
  if (!is.null(p21_check$conditions)) {
    conditions <- list()
    for (item in p21_check$conditions) {
      if (is.list(item) && !is.null(item$name)) {
        p21_op <- item$operator %||% item$type
        herald_op <- p21_operator_map[[p21_op]] %||% p21_op
        cond <- list(name = item$name, operator = herald_op)
        if (!is.null(item$value)) cond$value <- item$value
        conditions <- c(conditions, list(cond))
      }
    }
    if (length(conditions) > 0L) return(list(all = conditions))
  }

  # Fallback: empty check
  list(all = list())
}

# =============================================================================
# Executability Detection
# =============================================================================

detect_executability <- function(p21_rule) {
  p21_type <- p21_rule$`P21 Type` %||% "Unknown"
  check <- p21_rule$Check %||% p21_rule$check

  # Not executable types
  if (p21_type %in% c("Schematron", "Property")) {
    return("Not Executable")
  }

  # Partially executable types
  if (p21_type %in% c("Lookup", "Metadata")) {
    return("Partially Executable")
  }

  # If check is empty or null
  if (is.null(check) || length(check) == 0L) return("Not Executable")

  # If check has type: schematron/property/metadata
  if (identical(check$type, "schematron") ||
      identical(check$type, "property")) {
    return("Not Executable")
  }
  if (identical(check$type, "metadata") ||
      identical(check$type, "lookup")) {
    return("Partially Executable")
  }

  # Check for P21 template variables (partially executable)
  check_str <- yaml::as.yaml(check)
  if (grepl("%Variables", check_str, fixed = TRUE) ||
      grepl("%Domain%", check_str, fixed = TRUE) ||
      grepl("%Variable\\.", check_str) ||
      grepl("%System\\.", check_str)) {
    return("Partially Executable")
  }

  "Fully Executable"
}

# =============================================================================
# Scope Detection
# =============================================================================

# Map SDTM variable prefixes to domains
sdtm_domain_map <- list(
  AE = list(classes = list("EVENTS"),    domains = list("AE")),
  DS = list(classes = list("EVENTS"),    domains = list("DS")),
  DV = list(classes = list("EVENTS"),    domains = list("DV")),
  CE = list(classes = list("EVENTS"),    domains = list("CE")),
  MH = list(classes = list("EVENTS"),    domains = list("MH")),
  HO = list(classes = list("EVENTS"),    domains = list("HO")),
  LB = list(classes = list("FINDINGS"),  domains = list("LB")),
  VS = list(classes = list("FINDINGS"),  domains = list("VS")),
  EG = list(classes = list("FINDINGS"),  domains = list("EG")),
  PE = list(classes = list("FINDINGS"),  domains = list("PE")),
  QS = list(classes = list("FINDINGS"),  domains = list("QS")),
  SC = list(classes = list("FINDINGS"),  domains = list("SC")),
  DA = list(classes = list("FINDINGS"),  domains = list("DA")),
  IE = list(classes = list("FINDINGS"),  domains = list("IE")),
  RS = list(classes = list("FINDINGS"),  domains = list("RS")),
  TU = list(classes = list("FINDINGS"),  domains = list("TU")),
  TR = list(classes = list("FINDINGS"),  domains = list("TR")),
  IS = list(classes = list("FINDINGS"),  domains = list("IS")),
  MI = list(classes = list("FINDINGS"),  domains = list("MI")),
  MB = list(classes = list("FINDINGS"),  domains = list("MB")),
  MS = list(classes = list("FINDINGS"),  domains = list("MS")),
  MO = list(classes = list("FINDINGS"),  domains = list("MO")),
  FT = list(classes = list("FINDINGS"),  domains = list("FT")),
  RP = list(classes = list("FINDINGS"),  domains = list("RP")),
  FA = list(classes = list("FINDINGS"),  domains = list("FA")),
  SR = list(classes = list("FINDINGS"),  domains = list("SR")),
  SS = list(classes = list("FINDINGS"),  domains = list("SS")),
  BS = list(classes = list("FINDINGS"),  domains = list("BS")),
  CP = list(classes = list("FINDINGS"),  domains = list("CP")),
  GF = list(classes = list("FINDINGS"),  domains = list("GF")),
  DD = list(classes = list("FINDINGS"),  domains = list("DD")),
  NV = list(classes = list("FINDINGS"),  domains = list("NV")),
  OE = list(classes = list("FINDINGS"),  domains = list("OE")),
  RE = list(classes = list("FINDINGS"),  domains = list("RE")),
  EX = list(classes = list("INTERVENTIONS"), domains = list("EX")),
  CM = list(classes = list("INTERVENTIONS"), domains = list("CM")),
  SU = list(classes = list("INTERVENTIONS"), domains = list("SU")),
  EC = list(classes = list("INTERVENTIONS"), domains = list("EC")),
  PR = list(classes = list("INTERVENTIONS"), domains = list("PR")),
  AG = list(classes = list("INTERVENTIONS"), domains = list("AG")),
  DM = list(classes = list("SPECIAL-PURPOSE"), domains = list("DM")),
  SV = list(classes = list("SPECIAL-PURPOSE"), domains = list("SV")),
  SE = list(classes = list("SPECIAL-PURPOSE"), domains = list("SE")),
  CO = list(classes = list("SPECIAL-PURPOSE"), domains = list("CO")),
  SM = list(classes = list("SPECIAL-PURPOSE"), domains = list("SM")),
  TA = list(classes = list("TRIAL DESIGN"), domains = list("TA")),
  TE = list(classes = list("TRIAL DESIGN"), domains = list("TE")),
  TI = list(classes = list("TRIAL DESIGN"), domains = list("TI")),
  TS = list(classes = list("TRIAL DESIGN"), domains = list("TS")),
  TV = list(classes = list("TRIAL DESIGN"), domains = list("TV")),
  TM = list(classes = list("TRIAL DESIGN"), domains = list("TM")),
  TD = list(classes = list("TRIAL DESIGN"), domains = list("TD"))
)

detect_scope <- function(p21_rule, std_prefix) {
  scope <- list(classes = list(), domains = list())

  # Check the Scope section
  p21_scope <- p21_rule$Scope %||% p21_rule$scope
  if (!is.null(p21_scope)) {
    if (!is.null(p21_scope$Classes$Include)) {
      scope$classes <- as.list(p21_scope$Classes$Include)
    } else if (!is.null(p21_scope$Classes) && is.character(p21_scope$Classes)) {
      scope$classes <- as.list(p21_scope$Classes)
    }
    if (!is.null(p21_scope$Domains$Include)) {
      scope$domains <- as.list(p21_scope$Domains$Include)
    } else if (!is.null(p21_scope$Domains) && is.character(p21_scope$Domains)) {
      scope$domains <- as.list(p21_scope$Domains)
    }
  }

  # If no scope found, try to infer from check variable names
  if (length(scope$classes) == 0L && length(scope$domains) == 0L) {
    check <- p21_rule$Check %||% p21_rule$check
    check_str <- if (!is.null(check)) yaml::as.yaml(check) else ""
    description <- p21_rule$Description %||% p21_rule$description %||% ""
    combined <- paste(check_str, description)

    if (std_prefix == "SD") {
      # Try to detect domain from variable names in check
      for (dom in names(sdtm_domain_map)) {
        # Look for domain-specific variables (e.g., AESEV, DSSTDTC, LBTEST)
        pattern <- sprintf("\\b%s[A-Z]{2,}", dom)
        if (grepl(pattern, combined)) {
          scope <- sdtm_domain_map[[dom]]
          break
        }
      }

      # Special cases from description
      if (length(scope$domains) == 0L) {
        if (grepl("\\bDM\\b", combined) && grepl("\\b(ARM|AGE|SEX|RACE|ETHNIC)", combined)) {
          scope <- sdtm_domain_map[["DM"]]
        } else if (grepl("\\bAE\\b", combined) || grepl("\\badverse", combined, ignore.case = TRUE)) {
          scope <- sdtm_domain_map[["AE"]]
        } else if (grepl("\\bTS\\b", combined) && grepl("\\b(TSPARM|TSVAL)", combined)) {
          scope <- sdtm_domain_map[["TS"]]
        }
      }

      # If still no scope, set broad SDTM classes
      if (length(scope$classes) == 0L && length(scope$domains) == 0L) {
        scope$classes <- list("EVENTS", "FINDINGS", "INTERVENTIONS",
                              "SPECIAL-PURPOSE", "TRIAL DESIGN",
                              "RELATIONSHIP", "ASSOCIATED PERSONS")
      }
    } else if (std_prefix == "AD") {
      # ADaM scope inference
      if (grepl("\\bADSL\\b", combined)) {
        scope$classes <- list("ADSL")
        scope$domains <- list("ADSL")
      } else if (grepl("\\bADBDS\\b|\\bBDS\\b", combined)) {
        scope$classes <- list("BDS")
      } else if (grepl("\\bOCCDS\\b|\\bADOCCDS\\b", combined)) {
        scope$classes <- list("OCCDS")
      } else if (grepl("\\bADTTE\\b", combined)) {
        scope$classes <- list("ADTTE")
      } else {
        scope$classes <- list("ADSL", "BDS", "OCCDS")
      }
    }
  }

  scope
}

# =============================================================================
# Authority/Provenance Extraction
# =============================================================================

extract_provenance <- function(p21_rule, p21_id) {
  cg_ids <- list()
  fda_ids <- list()
  core_id <- NULL
  source_doc <- p21_rule$Source %||%
    p21_rule$`Source Document` %||%
    p21_rule$source_doc %||%
    paste("P21 rule", p21_id)

  authorities <- p21_rule$Authorities
  if (!is.null(authorities) && is.list(authorities)) {
    for (auth in authorities) {
      standards <- auth$Standards
      if (is.null(standards)) next
      for (std in standards) {
        refs <- std$References
        if (is.null(refs)) next
        for (ref in refs) {
          rid <- ref$`Rule Identifier`$Id %||% ref$`Rule Identifier`
          if (is.null(rid)) next
          rid <- as.character(rid)
          if (grepl("^CG\\d", rid)) {
            cg_ids <- c(cg_ids, list(rid))
          } else if (grepl("^FDAB?\\d|^FDA-", rid)) {
            fda_ids <- c(fda_ids, list(rid))
          } else if (grepl("^CORE-", rid)) {
            core_id <- rid
          }
        }
        # Also extract source_doc from standard name + version
        std_name <- std$Name %||% ""
        std_ver <- std$Version %||% ""
        if (nchar(std_name) > 0L && nchar(std_ver) > 0L) {
          source_doc <- paste0(std_name, " v", std_ver)
        } else if (nchar(std_name) > 0L) {
          source_doc <- std_name
        }
      }
    }
  }

  list(
    p21_id     = p21_id,
    core_id    = core_id,
    cg_ids     = cg_ids,
    fda_ids    = fda_ids,
    source_doc = source_doc
  )
}

# =============================================================================
# Outcome Extraction
# =============================================================================

extract_outcome <- function(p21_rule, herald_id) {
  message <- p21_rule$Outcome$Message %||%
    p21_rule$Outcome$message %||%
    p21_rule$outcome$Message %||%
    p21_rule$outcome$message %||%
    paste("Rule", herald_id, "violation")

  # Map P21 severity
  severity_raw <- p21_rule$Outcome$Severity %||%
    p21_rule$Outcome$severity %||%
    p21_rule$outcome$Severity %||%
    p21_rule$outcome$severity %||%
    p21_rule$Check$severity %||%  # Some Schematron rules put severity in Check
    "Error"

  severity <- switch(
    tolower(as.character(severity_raw)),
    "error"   = "Error",
    "reject"  = "Error",
    "warning" = "Warning",
    "notice"  = "Notice",
    "info"    = "Notice",
    "Error"
  )

  list(
    message  = message,
    severity = severity
  )
}

# =============================================================================
# Main Conversion Function
# =============================================================================

convert_rule <- function(p21_rule, p21_id) {
  # Determine standard from P21 ID prefix
  std_prefix <- sub("(\\D+)\\d+.*", "\\1", p21_id)
  std_info <- p21_to_herald_std[[std_prefix]]

  if (is.null(std_info)) {
    return(NULL)
  }

  # For OD rules, use DD counter
  counter_key <- if (std_prefix == "OD") "DD" else std_prefix

  # Generate herald ID
  herald_num <- counters[[counter_key]]
  counters[[counter_key]] <<- herald_num + 1L
  herald_id <- sprintf("%s-%04d", std_info$prefix, herald_num)

  # Extract description
  description <- p21_rule$Description %||%
    p21_rule$description %||%
    paste("Converted from P21 rule", p21_id)

  # Get P21 type
  p21_type <- p21_rule$`P21 Type` %||% "Unknown"

  # Convert check
  p21_check <- p21_rule$Check %||% p21_rule$check
  herald_check <- convert_check(p21_check, p21_type)

  # Detect category
  p21_cat <- p21_rule$Category %||%
    p21_rule$category %||%
    p21_rule$`Rule Type` %||%
    p21_rule$rule_type %||%
    "Unknown"
  herald_cat <- if (!is.null(p21_cat) && p21_cat %in% names(p21_category_map)) {
    p21_category_map[[p21_cat]]
  } else {
    "Consistency"
  }

  # Detect sensitivity
  p21_sens <- p21_rule$Sensitivity %||% p21_rule$sensitivity %||% "Record"
  herald_sens <- if (!is.null(p21_sens) && p21_sens %in% names(p21_sensitivity_map)) {
    p21_sensitivity_map[[p21_sens]]
  } else {
    "Record"
  }

  # Build herald rule
  herald_rule <- list(
    id             = herald_id,
    version        = 1L,
    status         = "Published",
    standard       = std_info$std,
    category       = herald_cat,
    sensitivity    = herald_sens,
    executability  = detect_executability(p21_rule),
    description    = description,
    scope          = detect_scope(p21_rule, std_prefix),
    check          = herald_check,
    outcome        = extract_outcome(p21_rule, herald_id),
    provenance     = extract_provenance(p21_rule, p21_id)
  )

  herald_rule
}

# =============================================================================
# Discover and Deduplicate P21 Rule Files
# =============================================================================

cat("Scanning P21 source directory...\n")

# Use only 2204.0 (latest) as primary source
p21_versions <- sort(list.dirs(p21_dir, recursive = FALSE, full.names = FALSE),
                     decreasing = TRUE)
cat(sprintf("  P21 versions available: %s\n", paste(p21_versions, collapse = ", ")))

# Build a map: rule_id -> best file path (highest priority IG)
rule_file_map <- list()

for (ver in p21_versions) {
  ver_dir <- file.path(p21_dir, ver)
  ig_dirs <- list.dirs(ver_dir, recursive = TRUE, full.names = TRUE)

  yaml_files <- list.files(ver_dir, pattern = "\\.ya?ml$",
                           recursive = TRUE, full.names = TRUE)

  for (yf in yaml_files) {
    rule_id <- sub("\\.ya?ml$", "", basename(yf))

    # Skip SEND rules
    if (grepl("^SE", rule_id)) next

    # Determine IG directory for priority
    rel_path <- sub(paste0(p21_dir, "/"), "", dirname(yf))
    parts <- strsplit(rel_path, "/")[[1L]]
    ig_name <- if (length(parts) >= 3L) parts[3L] else if (length(parts) >= 2L) parts[2L] else ""
    priority <- ig_priority[[ig_name]] %||% 50L

    # Keep highest priority version
    existing <- rule_file_map[[rule_id]]
    if (is.null(existing) || priority > existing$priority) {
      rule_file_map[[rule_id]] <- list(path = yf, priority = priority, ig = ig_name)
    }
  }
}

cat(sprintf("  Unique rule IDs (excl. SEND): %d\n", length(rule_file_map)))

# Filter by standard if requested
if (!is.null(target_standard)) {
  target_prefix <- toupper(substr(target_standard, 1, 2))
  rule_file_map <- rule_file_map[grepl(sprintf("^%s", target_prefix), names(rule_file_map))]
  cat(sprintf("  Filtered to %d rules for standard '%s'\n",
              length(rule_file_map), target_standard))
}

# Remove already-converted
before_skip <- length(rule_file_map)
rule_file_map <- rule_file_map[!names(rule_file_map) %in% existing_p21_ids]
skipped_existing <- before_skip - length(rule_file_map)
cat(sprintf("  Skipping %d already-converted rules\n", skipped_existing))
cat(sprintf("  Rules to convert: %d\n", length(rule_file_map)))

# Apply limit
rule_ids <- names(rule_file_map)
if (is.finite(rule_limit) && length(rule_ids) > rule_limit) {
  rule_ids <- rule_ids[seq_len(rule_limit)]
  cat(sprintf("  Limited to first %d rules\n", rule_limit))
}

# Sort rule IDs for deterministic output
rule_ids <- sort(rule_ids)

# =============================================================================
# Convert Each Rule
# =============================================================================

cat("\nConverting...\n")

converted   <- 0L
skipped     <- 0L
errored     <- 0L
by_type     <- list()
by_exec     <- list()

for (rid in rule_ids) {
  entry <- rule_file_map[[rid]]
  pf <- entry$path

  p21_rule <- tryCatch(
    yaml::read_yaml(pf),
    error = function(e) {
      cat(sprintf("  ERROR: Failed to parse %s: %s\n", rid, conditionMessage(e)))
      NULL
    }
  )

  if (is.null(p21_rule)) {
    errored <- errored + 1L
    next
  }

  herald_rule <- convert_rule(p21_rule, rid)

  if (is.null(herald_rule)) {
    skipped <- skipped + 1L
    next
  }

  # Track P21 type stats
  p21_type <- p21_rule$`P21 Type` %||% "Unknown"
  by_type[[p21_type]] <- (by_type[[p21_type]] %||% 0L) + 1L
  by_exec[[herald_rule$executability]] <- (by_exec[[herald_rule$executability]] %||% 0L) + 1L

  # Determine output path
  std_prefix <- sub("(\\D+)\\d+.*", "\\1", rid)
  std_info <- p21_to_herald_std[[std_prefix]]
  output_dir <- file.path(repo_root, "rules", std_info$dir)
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  output_path <- file.path(output_dir, paste0(herald_rule$id, ".yaml"))

  if (dry_run) {
    cat(sprintf("  [DRY RUN] %s -> %s (%s, %s)\n",
                rid, herald_rule$id, herald_rule$executability, p21_type))
  } else {
    yaml_out <- yaml::as.yaml(herald_rule, indent.mapping.sequence = TRUE)
    writeLines(yaml_out, output_path)
  }

  converted <- converted + 1L

  # Progress indicator every 100 rules
  if (converted %% 100L == 0L) {
    cat(sprintf("  ... %d rules converted\n", converted))
  }
}

# =============================================================================
# Summary
# =============================================================================

cat(sprintf("\n=== Conversion Summary ===\n"))
cat(sprintf("  Converted:        %d\n", converted))
cat(sprintf("  Skipped (dup):    %d\n", skipped))
cat(sprintf("  Skipped (exist):  %d\n", skipped_existing))
cat(sprintf("  Errors:           %d\n", errored))
cat(sprintf("  Total processed:  %d\n", converted + skipped + errored))

cat("\n  By P21 Type:\n")
for (tp in sort(names(by_type))) {
  cat(sprintf("    %-15s %d\n", tp, by_type[[tp]]))
}

cat("\n  By Executability:\n")
for (ex in sort(names(by_exec))) {
  cat(sprintf("    %-25s %d\n", ex, by_exec[[ex]]))
}

if (dry_run) {
  cat("\n  (Dry run -- no files written)\n")
}

cat("\nDone.\n")
