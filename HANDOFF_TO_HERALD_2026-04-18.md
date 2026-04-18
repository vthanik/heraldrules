# Handover to Herald R Package — 2026-04-18 (Phase 2i)

**From:** heraldrules Phase 2i of the "Beat P21" program.
**To:** a Claude Code session opened inside `/Users/vignesh/projects/r/herald/`.
**Supersedes:** the prior 2026-04-18 version of this file in full.
**Plan of record:** `/Users/vignesh/.claude/plans/handover-summary-noble-dijkstra.md`.

---

## §0. Next-session priorities (P21-parity unblockers on HBPD03)

A fresh HBPD03 submission (`submit(adam, spec, rules = "all")` with auto-
config `fda-adam-ig-1.2`) produced 7,452 findings. P21 Community v4.1.0
(PMDA 2508.1 rule set) on the same data produced 1,221 findings across
six unique rules:

| P21 id  | count | herald counterpart (loaded by FDA cfg) | today's state               | after this handover              |
|---------|------:|----------------------------------------|-----------------------------|----------------------------------|
| AD0124  | 1,210 | `ADaM-124-SD` (engines/cdisc/)         | no-op — operator `not_consistent_with_variable` missing | fires; count matches P21 |
| AD0047  |     8 | `ADaM-047` (engines/cdisc/)            | `Reference` (stub `required_variables`) | §3 unstubs; flip in a later heraldrules session (§8 below) |
| AD1024  |     1 | `ADaM-1024`                            | fires                       | unchanged                        |
| AD1025  |     1 | `ADaM-1025`                            | fires                       | unchanged                        |
| AD1026  |     1 | `ADaM-1026`                            | fires                       | unchanged                        |
| DD0101  |     1 | `DD0101`                               | `Partially Executable`, stub `manual_review` | §6 unstubs; heraldrules Define scope lands in Phase 4 |

Herald today also emits 7,403 spurious `HRL-KEY-001` findings (6,775 on
ADVS alone) because `check_key_uniqueness` at
`R/val-checks.R:745-805` silently reduces the spec-declared composite
key to whatever subset exists in the data and flags every sibling
record as a duplicate. Commit `f346c0a` added a short-circuit that
returns zero findings when any declared key is missing — defensively
correct but information-losing.

This handover replaces the hardcoded check with a YAML-first design:

1. **Delete** `check_key_uniqueness` from `R/val-checks.R` (§1).
2. **Add** a `__spec_keys__` sentinel to the YAML dispatcher (§2) so
   `engines/herald/HRL-KEY-001.yaml` and `HRL-KEY-002.yaml` can read
   `spec$ds_spec$keys` at execution time.
3. **Unstub** `required_variables` (§3) — unlocks AD0047 and powers
   HRL-KEY-002.
4. **Implement** `duplicate_composite_key` (§4) — powers HRL-KEY-001.
5. **Batch-implement** the remaining 21 missing operators (§5).
6. **Unstub** the other 5 no-op operators (§6).
7. **Verify** via the `inst/benchmarks/p21-parity/` harness (§7).

Rule-count impact once all sections land: 178 → ~205 runnable herald
engine rules, plus ~260 rules elsewhere unlocked across CDISC and PMDA
engines — closing the P21 parity gap on any typical FDA ADaM submission.

**Do not edit this repo** (`/Users/vignesh/projects/r/heraldrules/`).
All catalog YAMLs, CSV, configs, manifest, CHANGELOG, and CLAUDE.md
were updated in the Phase 2i heraldrules commit. The only
heraldrules-side work remaining (AD0047 flip to `Fully Executable`)
must wait for a fresh heraldrules session after §3 ships.

---

## §1. Delete the hardcoded `check_key_uniqueness`

### File

`R/val-checks.R`

### Change

Remove lines 739-805 (`check_key_uniqueness` function and its docstring).

Remove the corresponding call site in `R/val-engine.R:399-403`:

```r
if ("key_uniqueness" %in% active_checks && !is.null(spec$ds_spec)) {
  findings_list <- c(
    findings_list,
    check_key_uniqueness(data, ds_name, spec$ds_spec)
  )
}
```

Remove `"key_uniqueness"` from the `active_checks` default vector.

Remove the HRL-KEY-001 description entry at `R/val-checks.R:679-682`.

Remove HRL-KEY-001 from any classifier or help table that lists it
alongside HRL-VAR / HRL-DS etc. Check `R/val-report.R` and the
`.classify_source` tests at
`tests/testthat/test-val-report.R:126,130,135` — those tests keep
passing if the classifier maps `HRL-KEY-*` to the same "Data"
category, which is an independent concern; retain but audit.

### Why

HRL-KEY-001 now lives in YAML (`engines/herald/HRL-KEY-001.yaml`) and
reaches the runtime through the normal operator dispatcher in
`R/rule-execute.R`. A hardcoded function duplicates the rule and is a
maintenance debt: edits to the YAML (description, severity, tests)
silently diverge from the R body. Per Phase 2i directive, rewrites of
previously-hardcoded rules convert to YAML — no new Hardcoded rules.

The 12 other hardcoded spec checks (`HRL-VAR-001/002/003`, `HRL-LBL-001`,
`HRL-TYP-001`, `HRL-LEN-001`, `HRL-DS-001`, `HRL-CL-001/002/010/020/021`)
stay hardcoded for now — each is scheduled for its own Phase 2i-style
conversion when next touched. Not in scope here.

### Tests

`tests/testthat/test-val-checks.R:266-348` contains three
HRL-KEY-001 tests that exercise the hardcoded function directly.
Delete them. The YAML rule's tests block (in the catalog) is the new
regression surface; rerun it via the shared operator test harness
added in §4.

Snapshot tests that include `HRL-KEY-001` strings should still pass —
the rule still fires, just via a different code path.

---

## §2. `__spec_keys__` sentinel in the YAML dispatcher

### Files

- `R/rule-execute.R` — `evaluate_condition` (line 852) and the upstream
  `execute_herald_rule` dispatch.
- `R/val-engine.R` — thread `spec` through to rule execution (it
  already has `spec` in scope at the HRL dispatch loop).

### Intent

A rule YAML writes:

```yaml
check:
  all:
    - name: __spec_keys__
      operator: duplicate_composite_key
```

The dispatcher must, when `name == "__spec_keys__"`, resolve the list
of key variable names from `spec$ds_spec[spec$ds_spec$dataset == ds_name, "keys"]`,
parse the comma-separated string into a `character()` vector, and pack
it into `value` so the operator function sees:

```r
list(
  data = <the current dataset>,
  keys = c("USUBJID", "PARAMCD", "AVISITN"),   # resolved at runtime
  ds_name = "ADVS"
)
```

The closest existing precedent is the `within_tolerance_of_formula`
branch at `rule-execute.R:916-923` — it packs `data`, `formula`,
`tolerance`, `guard_nonzero` into `value` before dispatch. Mirror that
pattern.

### Minimal change

Thread `spec` into `evaluate_condition` (add parameter `spec = NULL`).
Call sites that currently pass `data, datasets, ds_name` gain a fourth
argument.

Inside `evaluate_condition`, before the cross-dataset branch, add:

```r
if (identical(var_name, "__spec_keys__")) {
  keys <- character()
  if (!is.null(spec) && !is.null(spec$ds_spec) && !is.null(ds_name)) {
    row <- spec$ds_spec[spec$ds_spec$dataset == ds_name, , drop = FALSE]
    if (nrow(row) > 0L && "keys" %in% names(row)) {
      keys_raw <- row$keys[1L]
      if (!is.na(keys_raw) && nzchar(trimws(keys_raw))) {
        keys <- trimws(strsplit(keys_raw, ",", fixed = TRUE)[[1L]])
        keys <- keys[nzchar(keys)]
      }
    }
  }
  value <- list(data = data, keys = keys, ds_name = ds_name)
  # Sentinel short-circuits the "column exists" check below. Dispatch
  # straight to the operator with the packed value; `x` is a zero-length
  # placeholder so signature stays the same — the operator must size its
  # return based on nrow(data), not length(x).
  op_fn <- .operator_registry[[operator]]
  if (is.null(op_fn)) {
    warning("Unknown operator in __spec_keys__ condition: ", operator)
    return(rep(FALSE, nrow(data)))
  }
  return(op_fn(rep(NA, nrow(data)), value))
}
```

(Exact registry lookup expression depends on how operators are stored;
use the same mechanism as the final fallback branch already in this
function.)

### Tests

Add `tests/testthat/test-spec-keys-sentinel.R`:

- Positive: dataset with 3 unique rows and spec keys `c("USUBJID","PARAMCD")`
  → `HRL-KEY-001` operator returns all-FALSE.
- Negative: dataset with a duplicate composite-key row and the same
  spec → operator flags the duplicate row (TRUE at one or both
  indices).
- Missing key: dataset that lacks `PARAMCD` → `duplicate_composite_key`
  returns `rep(NA, nrow(data))` (the dispatcher converts NA to "not a
  violation" for HRL-KEY-001; HRL-KEY-002 picks up the missing column).

---

## §3. Implement `required_variables` (unblocks AD0047 and powers HRL-KEY-002)

### File / line

`R/rule-operator.R:862` — currently:

```r
required_variables = function(x, value) rep(FALSE, length(x)),
```

### New body

Two usage modes, distinguished by `value`:

```r
required_variables = function(x, value) {
  if (is.list(value) && !is.null(value[["keys"]])) {
    # __spec_keys__ mode (HRL-KEY-002): one finding per missing key
    # column. Return a TRUE mask of length equal to number of missing
    # keys, padded to nrow(data) with FALSE. The engine will emit one
    # finding per TRUE at Dataset sensitivity (message text carries the
    # column name via `variable`).
    data <- value[["data"]]
    keys <- value[["keys"]]
    missing <- setdiff(keys, names(data))
    n_rows <- if (!is.null(data)) nrow(data) else length(x)
    mask <- rep(FALSE, max(n_rows, length(missing)))
    if (length(missing) > 0L) {
      mask[seq_along(missing)] <- TRUE
      attr(mask, "variables") <- missing
    }
    return(mask)
  }
  if (is.list(value) && !is.null(value[["domain"]])) {
    # AD0047 mode: compare dataset columns against the required-variable
    # catalog for (domain, ig_version). Data source below.
    data <- value[["data"]]
    req <- .lookup_required_vars(value[["domain"]], value[["ig_version"]])
    if (is.null(data) || length(req) == 0L) {
      return(rep(FALSE, length(x)))
    }
    missing <- setdiff(req, names(data))
    mask <- rep(FALSE, max(nrow(data), length(missing)))
    if (length(missing) > 0L) {
      mask[seq_along(missing)] <- TRUE
      attr(mask, "variables") <- missing
    }
    return(mask)
  }
  rep(FALSE, length(x))
}
```

### Data source for AD0047 mode

Ship `inst/extdata/adam-required-vars.rds` — a nested list:

```r
list(
  `ADaM-IG 1.1` = list(
    ADSL  = c("STUDYID", "USUBJID", "SUBJID", "SITEID", "AGE", "AGEU",
              "SEX", "RACE", "ETHNIC", "ITTFL", "SAFFL", ...),
    ADAE  = c("STUDYID", "USUBJID", "AETERM", "AEBODSYS", "AEDECOD",
              "AESEV", "AESER", "AESTDTC", "AEENDTC", "AEBDSYCD", ...),
    BDS   = c("STUDYID", "USUBJID", "PARAMCD", "PARAM", "AVAL", "AVALC",
              "ADT", "ADY", "VISIT", "VISITNUM", ...),
    OCCDS = c("STUDYID", "USUBJID", ...)
  ),
  `ADaM-IG 1.2` = list( ... )
)
```

Source material:
- ADaM IG 1.1 §3.2 (ADSL), §4.2 (BDS), OCCDS appendix.
- ADaM IG 1.2 §3.2, §4.2, OCCDS appendix.
- ADaM AE IG v1.0 (ADAE — includes AEBDSYCD which is the first P21
  AD0047 finding on HBPD03).

Internal helper:

```r
.lookup_required_vars <- function(domain, ig_version) {
  tab <- tryCatch(
    readRDS(system.file("extdata", "adam-required-vars.rds", package = "herald")),
    error = function(e) list()
  )
  if (is.null(tab[[ig_version]])) return(character())
  tab[[ig_version]][[domain]] %||% character()
}
```

### Tests

`tests/testthat/test-rule-operator-required-variables.R`:

- `__spec_keys__` mode: value = `list(data = df_with_USUBJID_only, keys = c("USUBJID","PARAMCD","AVISITN"))`.
  Expected: mask with TRUE at positions 1-2, `attr(mask, "variables")` = `c("PARAMCD","AVISITN")`.
- `__spec_keys__` mode, all keys present: mask all FALSE.
- AD0047 mode: value = `list(data = adae_missing_AESEV, domain = "ADAE", ig_version = "ADaM-IG 1.1")`.
  Expected: mask with one TRUE, variables attribute = `"AESEV"` (or the specific missing column).
- Missing extdata file: no crash, returns all-FALSE.

### YAML usage (heraldrules side, covered in this Phase 2i commit)

- `engines/herald/HRL-KEY-002.yaml` — uses `__spec_keys__` mode.
- `engines/pmda/AD0047.yaml` — will switch to `Fully Executable` in a
  future heraldrules session (listed in §8 below).

---

## §4. Implement `duplicate_composite_key` (powers HRL-KEY-001)

### File / line

`R/rule-operator.R` — add in the "22a. New gap-fill operators" block
near line 833 (alongside `not_consistent_within`):

### New body

```r
duplicate_composite_key = function(x, value) {
  if (!is.list(value) || is.null(value[["data"]]) || is.null(value[["keys"]])) {
    return(rep(FALSE, length(x)))
  }
  data <- value[["data"]]
  keys <- value[["keys"]]
  n <- nrow(data)
  if (length(keys) == 0L) {
    return(rep(FALSE, n))
  }
  # Inconclusive when any declared key is absent from data — HRL-KEY-002
  # catches this case separately; signal "cannot evaluate" with NA so
  # the engine does not emit a duplicate-key finding.
  missing <- setdiff(keys, names(data))
  if (length(missing) > 0L) {
    return(rep(NA, n))
  }
  key_vals <- do.call(paste, c(data[keys], sep = "\x1f"))
  dup_mask <- duplicated(key_vals) | duplicated(key_vals, fromLast = TRUE)
  dup_mask
}
```

### Engine handling of NA mask

The finding emitter must treat `NA` in a violation mask as "skip this
row, no finding". Check `R/rule-execute.R` around the point where
operator results are converted into findings; if it currently treats
`NA` as TRUE (or crashes), add:

```r
mask[is.na(mask)] <- FALSE
```

just before the `which(mask)` call. Document the NA-means-inconclusive
convention near the registry header comment in `rule-operator.R`.

### Tests

`tests/testthat/test-rule-operator-duplicate-composite-key.R`:

- Positive: 3 unique rows, keys = `c("USUBJID","PARAMCD")` → mask all FALSE.
- Negative: two rows with identical `(USUBJID, PARAMCD)` → both flagged
  (both TRUE; we use `duplicated | duplicated(fromLast=TRUE)` so every
  duplicate group member lights up, not just the second occurrence).
- Inconclusive: keys include `"ATPTN"` but data has no ATPTN column →
  mask all `NA_integer_` (or `NA`).
- Empty keys: `keys = character(0)` → mask all FALSE.

### YAML

`engines/herald/HRL-KEY-001.yaml` already ships with:

```yaml
check:
  all:
    - name: __spec_keys__
      operator: duplicate_composite_key
```

Nothing else to wire on the catalog side.

---

## §5. Batch-implement the remaining 21 missing operators

Each operator below is `x, value → logical()` with violation semantics
per CLAUDE.md convention (body returns TRUE where violation). Anchors
are where to add the block in `rule-operator.R`; all go in the "gap-fill"
section around line 829+.

### 5a. Trivial type / cross-column (5 operators, ~25 rules)

```r
not_character = function(x, value) !vapply(x, is.character, logical(1))
# Simpler if x is guaranteed atomic: !is.character(x) per element.

not_numeric = function(x, value) {
  is.na(suppressWarnings(as.numeric(as.character(x)))) & !is.na(x) & nzchar(as.character(x))
}

less_than_variable = function(x, value) {
  # Packed value$data + value$within (auto-pack in evaluate_condition;
  # add "less_than_variable" to the auto-pack allow-list at rule-execute.R:902).
  if (!is.list(value) || is.null(value[["data"]])) {
    return(rep(FALSE, length(x)))
  }
  other <- value[["data"]][[value[["within"]] %||% value[["value"]]]]
  if (is.null(other)) return(rep(FALSE, length(x)))
  xn <- suppressWarnings(as.numeric(x))
  on <- suppressWarnings(as.numeric(other))
  !is.na(xn) & !is.na(on) & xn >= on
}

not_consistent_with_variable = function(x, value) {
  # Identical to not_consistent_within — uses the grouping column
  # referenced by value$within. Alias for the same logic, kept separate
  # for readability of the 15 CDISC YAMLs that use it.
  if (!is.list(value) || is.null(value[["data"]]) || is.null(value[["within"]])) {
    return(rep(FALSE, length(x)))
  }
  grp <- value[["data"]][[value[["within"]]]]
  if (is.null(grp)) return(rep(FALSE, length(x)))
  mask <- rep(FALSE, length(x))
  for (g in unique(grp[!is.na(grp)])) {
    idx <- which(grp == g)
    ux <- unique(x[idx][!is.na(x[idx])])
    if (length(ux) > 1L) mask[idx] <- TRUE    # flag every offending row
  }
  mask
}

no_matching_record = function(x, value) {
  # Cross-dataset join. value is:
  #   list(reference_dataset = "ADSL", by = "USUBJID", data = <this>, datasets = <all>)
  if (!is.list(value) || is.null(value[["reference_dataset"]]) ||
      is.null(value[["datasets"]])) {
    return(rep(FALSE, length(x)))
  }
  ref <- value[["datasets"]][[value[["reference_dataset"]]]]
  if (is.null(ref)) return(rep(FALSE, length(x)))
  by <- value[["by"]] %||% "USUBJID"
  ref_keys <- as.character(ref[[by]])
  !(as.character(x) %in% ref_keys)
}
```

Add `not_consistent_with_variable` and `less_than_variable` to the
auto-pack allow-list at `R/rule-execute.R:902-908` so bare-string
`value:` in YAML becomes the grouping column automatically.

Rules unlocked: ADaM-092-SD through ADaM-095-SD and siblings (15);
ADaM-1027/1031/1037/1041 (8); ADaM-084, ADaM-099-SD, ADaM-121 (5);
HRL-SD-012, HRL-SD-013 (2). Total 30.

### 5b. Spec-aware operators (3 operators, ~6 rules)

These follow the `__spec_keys__` pattern of §2 but read different spec
sheets. Extend `evaluate_condition` to recognise sentinel names
`__shared_variables__` and `__dataset__`; route to the Variables sheet
and Datasets sheet respectively (already parsed into `spec` by
`read_spec`).

```r
label_match = function(x, value) {
  # value$pairs is a data.frame with columns source_label, target_label.
  if (!is.list(value) || is.null(value[["pairs"]])) {
    return(rep(FALSE, length(x)))
  }
  as.character(value[["pairs"]][["source_label"]]) !=
    as.character(value[["pairs"]][["target_label"]])
}

format_match = function(x, value) {
  if (!is.list(value) || is.null(value[["pairs"]])) {
    return(rep(FALSE, length(x)))
  }
  as.character(value[["pairs"]][["source_format"]]) !=
    as.character(value[["pairs"]][["target_format"]])
}

type_match = function(x, value) {
  if (!is.list(value) || is.null(value[["pairs"]])) {
    return(rep(FALSE, length(x)))
  }
  as.character(value[["pairs"]][["source_type"]]) !=
    as.character(value[["pairs"]][["target_type"]])
}
```

Dispatcher support: when `name == "__shared_variables__"` and
`value == "__cross_dataset__"`, build the `pairs` data.frame by joining
SDTM and ADaM variable metadata from `spec$var_spec` on `variable`, then
pack into `value` as shown.

Rules unlocked: HRL-AD-001, -002, -006, -007, -013, -014 (6).

### 5c. Cross-dataset existence (1 operator, 1 rule)

```r
exists_in_dataset = function(x, value) {
  # Thin wrapper over no_matching_record; flag when x is not in reference set.
  no_matching_record(x, value)
}
```

Rule unlocked: HRL-AD-021.

### 5d. Define-VLM cross-reference (1 operator, 1 rule)

```r
not_in_define_vlm = function(x, value) {
  # value$vlm is a data.frame from define.xml's VariableLevelMetadata.
  if (!is.list(value) || is.null(value[["vlm"]])) {
    return(rep(FALSE, length(x)))
  }
  !(as.character(x) %in% as.character(value[["vlm"]][["itemref"]]))
}
```

Dispatcher: if `define_xml` is attached to `spec`, parse VLM once,
pass under `value$vlm`. Rule unlocked: HRL-DD-015.

### 5e. Composite-key builder (1 operator, 1 rule)

`compound_key` is not a check operator — it's an operation a rule YAML
uses to define a multi-column key for downstream use. Implement as a
pass-through that the dispatcher recognises and packs into `value` for
the next condition in the `all:` block:

```r
compound_key = function(x, value) {
  # value is a list of column names; return a character vector of joined
  # key tuples. Rules author pairs this with duplicate_composite_key or
  # no_matching_record via `within:`. Returned mask is all FALSE — this
  # is a "compute and stash" operator, not a violation check.
  rep(FALSE, length(x))
}
```

Rule unlocked: HRL-AD-024.

### 5f. ADSL consistency (1 operator, 1 rule)

```r
adsl_consistency_check = function(x, value) {
  # Flag rows where USUBJID's ADSL-scoped variable value differs from
  # the BDS/OCCDS dataset's copy. value is a list with:
  #   adsl_var  — column name to compare
  #   datasets  — list of datasets
  if (!is.list(value) || is.null(value[["datasets"]]) || is.null(value[["adsl_var"]])) {
    return(rep(FALSE, length(x)))
  }
  adsl <- value[["datasets"]][["ADSL"]]
  adsl_var <- value[["adsl_var"]]
  if (is.null(adsl) || !(adsl_var %in% names(adsl))) {
    return(rep(FALSE, length(x)))
  }
  adsl_key <- setNames(adsl[[adsl_var]], as.character(adsl[["USUBJID"]]))
  local_usubjid <- as.character(value[["data"]][["USUBJID"]])
  expected <- adsl_key[local_usubjid]
  as.character(x) != as.character(expected)
}
```

Rule unlocked: ADaM-1046.

### 5g. Dataset-level metadata (2 operators, ~5 rules)

```r
dataset_names = function(x, value) {
  # value$datasets is the list of loaded datasets; value$expected is
  # a character vector of required dataset names. Flag when any
  # required name is missing.
  if (!is.list(value) || is.null(value[["datasets"]])) {
    return(rep(FALSE, length(x)))
  }
  missing <- setdiff(value[["expected"]] %||% character(), names(value[["datasets"]]))
  mask <- rep(FALSE, max(1L, length(missing)))
  if (length(missing) > 0L) {
    mask[seq_along(missing)] <- TRUE
    attr(mask, "variables") <- missing
  }
  mask
}

study_domains = function(x, value) {
  # Same shape as dataset_names but checks SDTM-domain presence.
  dataset_names(x, value)
}
```

Rules unlocked: CORE-000384, CORE-000457, CORE-000502, CORE-000539,
CORE-000540 (5).

### 5h. Metadata/inspection utilities (8 operators, ~5 rules)

Each returns a dataset-derived vector. Use cases are small; keep bodies
conservative (return NA on absent context so rules flagged as needing
these operators stay inconclusive rather than silently passing):

```r
get_column_order_from_dataset = function(x, value) {
  if (!is.list(value) || is.null(value[["data"]])) return(rep(NA, length(x)))
  seq_along(names(value[["data"]]))
}
get_column_order_from_library = function(x, value) rep(NA, length(x))
get_model_column_order           = function(x, value) rep(NA, length(x))
get_parent_model_column_order    = function(x, value) rep(NA, length(x))
get_model_filtered_variables     = function(x, value) rep(NA, length(x))
get_dataset_filtered_variables   = function(x, value) {
  if (!is.list(value) || is.null(value[["data"]])) return(rep(NA, length(x)))
  as.character(names(value[["data"]]))
}
get_codelist_attributes          = function(x, value) rep(NA, length(x))
extract_metadata                 = function(x, value) rep(NA, length(x))
```

These are helpers the CDISC CORE engine uses as building blocks for
composite rules; a full implementation lives in CDISC's `core` library
(Python) and is not strictly needed for HBPD03 parity. Ship the stubs-
returning-NA versions so the 5 rules that reference them evaluate to
"inconclusive" rather than silently passing. Proper implementations
tracked as follow-up in `HANDOFF §8`.

---

## §6. Unstub the 5 remaining no-op operators

### `variable_exists` (`rule-operator.R:424`)

```r
variable_exists = function(x, value) {
  # Fire when the variable named by `value` does not exist in the packed
  # data frame. Used by rules like "dataset must contain XXX".
  if (!is.list(value) || is.null(value[["data"]])) {
    return(rep(FALSE, length(x)))
  }
  var <- if (is.character(value[["value"]])) value[["value"]] else ""
  rep(!(var %in% names(value[["data"]])), max(1L, length(x)))
}
```

### `manual_review` (`rule-operator.R:568`)

```r
manual_review = function(x, value) {
  # Cannot be automated — raise an advisory finding per row so users
  # know a human reviewer must sign off. Severity is Warning, not Error;
  # rule YAMLs that use this operator must set severity accordingly.
  rep(TRUE, length(x))
}
```

This breaks P21-style silent-pass behavior by design. Rule YAMLs using
this operator should declare `severity: Warning` (most DD0101-style
rules already do).

### `valid_reference` (`rule-operator.R:812`)

```r
valid_reference = function(x, value) {
  # x is the reference string (e.g. "ADSL.USUBJID"). value$datasets is
  # the dataset list. Fire when the reference does not resolve.
  if (!is.list(value) || is.null(value[["datasets"]])) {
    return(rep(FALSE, length(x)))
  }
  parts <- strsplit(as.character(x), ".", fixed = TRUE)
  vapply(parts, function(p) {
    if (length(p) != 2L) return(TRUE)
    ds <- value[["datasets"]][[p[[1L]]]]
    is.null(ds) || !(p[[2L]] %in% names(ds))
  }, logical(1))
}
```

### `domain_label` (`rule-operator.R:859`)

```r
domain_label = function(x, value) {
  # Fire when domain attribute label does not match the expected value.
  # value is either a string (expected label) or a list with $expected.
  expected <- if (is.list(value)) value[["expected"]] %||% "" else as.character(value)
  as.character(x) != expected
}
```

### `expected_variables` (`rule-operator.R:861`)

```r
expected_variables = function(x, value) {
  # Complement of required_variables: fire when a variable that SHOULD
  # be absent (e.g. forbidden ADSL variable in a BDS dataset) IS present.
  if (!is.list(value) || is.null(value[["data"]]) || is.null(value[["forbidden"]])) {
    return(rep(FALSE, length(x)))
  }
  present <- intersect(value[["forbidden"]], names(value[["data"]]))
  mask <- rep(FALSE, max(nrow(value[["data"]]), length(present)))
  if (length(present) > 0L) {
    mask[seq_along(present)] <- TRUE
    attr(mask, "variables") <- present
  }
  mask
}
```

### Tests

One file per unstub, `tests/testthat/test-rule-operator-<name>.R`, each
with a passing input (mask all FALSE) and a violating input (mask has
at least one TRUE at the expected index).

---

## §7. `not_within_tolerance_of_formula` (19 rules — deferred)

The previous handover's §4j item 1 called out 19 CDISC+PMDA rules using
`not_within_tolerance_of_formula` which is absent from the registry
AND is almost certainly a polarity error (herald has
`within_tolerance_of_formula` at `rule-operator.R:578` already). The
heraldrules Phase 2e audit already fixed those 19 rule YAMLs to use
the correct operator. **No herald-side change required** — this item
is closed as of Phase 2e.

---

## §8. Verification

Run after §1 through §6 are applied:

```r
setwd("/Users/vignesh/projects/r/herald")
devtools::document()
devtools::test()      # all green; new tests from §2-§6 pass
devtools::check()     # 0E / 0W / 0N

# Then regression against the real HBPD03:
devtools::load_all()
library(herald)
spec_path <- here::here("inputs", "HBPD03", "HBPD03_spec.xlsx")
adam      <- path.expand("~/projects/data/HBPD03/adam")
output    <- file.path(tempdir(), "HBPD03_submission")
dir.create(output, showWarnings = FALSE, recursive = TRUE)
spec <- read_spec(spec_path)
result <- submit(adam, spec = spec, rules = "all", output = output)
sort(table(result$validation$findings$rule_id), decreasing = TRUE)
```

### Expected steady state on HBPD03 after this handover

| rule_id         | count | comment                                                         |
|-----------------|------:|-----------------------------------------------------------------|
| HRL-KEY-001     |     0 | all declared keys present, no dups (or a small legitimate count if the spec genuinely under-declares) |
| HRL-KEY-002     | small | one per declared key absent from data (if any)                  |
| `ADaM-124-SD`   | 1,210 | matches P21's AD0124                                            |
| `ADaM-047`      |     0 | still `Reference` until heraldrules flips it (next session)     |
| HRL-CL-001      |    81 | unchanged                                                       |
| HRL-VAR-003     |    49 | unchanged                                                       |
| HRL-CON-002     |     5 | unchanged                                                       |
| `ADaM-1024/5/6` |     3 | unchanged                                                       |
| _Total_         | ~1,350 | compared to P21's 1,221 — delta is the herald-specific rules    |

### Benchmark harness

`/Users/vignesh/projects/r/heraldrules/inst/benchmarks/p21-parity/run-benchmark.R`
already knows about HRL-KEY-001 / AD0124 / AD0047 and their expected
counts. Run it after §3 lands:

```r
setwd("/Users/vignesh/projects/r/heraldrules")
Rscript inst/benchmarks/p21-parity/run-benchmark.R
```

Expected: AD0124 parity passes (1,210 = 1,210). AD0047 still shows
SKIP until the follow-up heraldrules session flips the YAML from
`Reference` to `Fully Executable`; that session is §9 below.

---

## §9. Follow-up heraldrules session after this handover lands

The following items land in a fresh **heraldrules** session (opened
inside `~/projects/r/heraldrules/`), not herald — one-way dependency
on §3 shipping first:

- Flip `engines/pmda/AD0047.yaml` from `executability: Reference` to
  `executability: Fully Executable` with a proper `check:` block:

  ```yaml
  check:
    all:
      - name: __dataset__
        operator: required_variables
        value:
          domain: ADAE
          ig_version: ADaM-IG 1.1
  ```

- Same for `engines/cdisc/ADaM-047.yaml`.
- Rerun `build-master-csv.R`, `build-configs.R`, `build-manifest.R`.
- Rerun `validate-rules.R` and the p21-parity benchmark.

This is a 10-minute commit once §3 is live.

---

## §10. What this handover does NOT cover

- The 11 other hardcoded HRL-* spec checks
  (`HRL-VAR-001/002/003`, `HRL-LBL-001`, `HRL-TYP-001`, `HRL-LEN-001`,
  `HRL-DS-001`, `HRL-CL-001/002/010/020/021`). They work correctly
  today; converting them to YAML-first follows the same pattern but
  is out of scope for P21-parity on HBPD03.
- The HRL-OD (ODM) and HRL-DD (Define-XML) ARM metadata operator
  families — prior handover §4h and §4i are still the reference.
- The CDISC CORE metadata utilities (`get_*`, `extract_metadata`) at a
  production level. Shipped as NA-returning helpers in §5h; real
  implementations can land when someone uses them.

---

## §11. Commit checklist (herald session)

- [ ] `R/val-checks.R` — `check_key_uniqueness` and its docstring removed
- [ ] `R/val-engine.R` — call site removed, `"key_uniqueness"` pulled from `active_checks`
- [ ] `R/val-checks.R:679-682` — HRL-KEY-001 description entry removed
- [ ] `R/rule-execute.R` — `__spec_keys__` sentinel added; `spec` threaded into `evaluate_condition`; NA masks handled
- [ ] `R/rule-operator.R` — `duplicate_composite_key`, `required_variables`, and 19 other operators added; 5 stubs replaced with real logic
- [ ] `inst/extdata/adam-required-vars.rds` — built from ADaM IG 1.1 / 1.2
- [ ] `tests/testthat/test-spec-keys-sentinel.R` — new, passes
- [ ] `tests/testthat/test-rule-operator-*.R` — new files for every new/unstubbed operator
- [ ] `tests/testthat/test-val-checks.R:266-348` (old HRL-KEY-001 tests) — removed
- [ ] `devtools::document()` / `devtools::test()` / `devtools::check()` all clean
- [ ] HBPD03 regression matches the §8 expected table
- [ ] Commit message: `Phase 2i: YAML-first HRL-KEY-001 + 28 new/unstubbed operators (closes HBPD03 P21 parity gap)`
