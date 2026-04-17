# Handover to herald R package — 2026-04-17 session

Source: `heraldrules` Claude session.
Target: `~/projects/r/herald/` (sibling repo).
Audience: a Claude session opened inside `~/projects/r/herald/` that will
apply, review, test, and commit the R-side changes.

## Files modified in the herald repo from this session

All changes live as uncommitted working-tree edits under
`~/projects/r/herald/`. Nothing has been staged or committed. Line counts
are from `git diff --stat` at time of handover.

| Status | Path | ± lines | Purpose |
|---|---|---|---|
| modified | `R/val-checks.R` | +310 / -9 | Extend `check_codelist()` for HRL-CL-002 type pre-check; add `check_paired_codelists()`, `check_predecessor_codelist()`, `check_codelist_id_exists()`; add `.types_compatible()` helper; extend `herald_rule_descriptions()` with 4 new entries + tightened HRL-CL-001 text. |
| modified | `R/val-engine.R` | +20 / -2 | Register `"codelist_spec"` in `.all_spec_checks`; wire the 3 spec-only checks into `validate_datasets()` after `"consistency"`; update `@section Rule IDs` and `@param ignore_spec_checks` in roxygen. |
| modified | `R/val-report.R` | +196 / -43 | Add `.compact_rows()` + `.group_findings_by_identity()` helpers; rewrite Issues-tab HTML loop (grouped, 9-col, Rows + Count); update Rules tab (new Variables column, multi-variant message detection); mirror grouping into XLSX Issues sheet (col_widths adjusted); mirror "N variants" into XLSX + JSON Rules sections. |
| modified | `inst/templates/report.html` | +6 / -2 | Issues tab `<thead>`: rename **Row** → **Rows**, add **Count** column (9 columns total). Rules tab `<thead>`: add **Variables** column (8 columns total). |
| modified | `man/validate.Rd` | +7 / -0 | Regenerated from roxygen — reflects new `@section Rule IDs` entries (HRL-CL-002/010/020/021) and expanded `ignore_spec_checks` description. Produced by `devtools::document()`. |
| modified | `tests/testthat/test-val-report.R` | +161 / -0 | 12 new cases for `.compact_rows()` (empty, singleton, run, scattered, NA, cap, 10k perf); 3 cases for `.group_findings_by_identity()`; 1 snapshot that HTML Issues tab renders `>1:10<` and header now has `Rows` + `Count`. |
| untracked | `tests/testthat/test-val-checks-codelist.R` | +310 / new file | 16 test_that blocks covering HRL-CL-002 type-mismatch pre-check, paired-codelist positive/negative/edge, Predecessor inheritance positive/negative/free-text, stray-id detector positive/negative/NULL-codelist, and a roster assertion that `herald_rule_descriptions()` names all five HRL-CL IDs. |

Total: **6 modified, 1 new, 656 insertions / 46 deletions**. Verified
clean against the full testthat suite (3191 PASS / 0 FAIL / 3 SKIP) and
`devtools::check()` (0 errors / 0 warnings / 0 notes).

Everything below gives the narrative reasons behind the diff so the
herald session can reconstruct or validate the intent independently.

## Why this handover exists

Per the rule added this session to `~/projects/r/heraldrules/CLAUDE.md`,
the sibling herald R package must not be edited directly from a
heraldrules session. All matching R-code work produced during today's
heraldrules rule-catalog additions needs to be re-applied (or reviewed)
from a dedicated herald session.

> **Working-tree state at time of handover:** this session already wrote
> the changes described below into `~/projects/r/herald/` (they are
> uncommitted working-tree edits). Either (a) the herald session can keep
> them as-is after review and commit, or (b) if the herald session wants
> to start clean, run `git stash` or `git restore .` in the herald repo
> and re-apply from this document. This handover is the single source of
> truth either way.

## Part A — New rules added to heraldrules (already committed/staged here)

Four new HRL-CL YAMLs plus one edit to HRL-CL-001:

| Rule | File | Semantics |
|---|---|---|
| HRL-CL-001 | `engines/herald/HRL-CL-001.yaml` | Message/description narrowed to "value not in Terms". Version **kept at 1** per the pre-CRAN no-bump rule. |
| HRL-CL-002 | `engines/herald/HRL-CL-002.yaml` (new) | Variable `data_type` mismatches referenced codelist's `data_type`. |
| HRL-CL-010 | `engines/herald/HRL-CL-010.yaml` (new) | Paired num/char vars (e.g. AGEGR1/AGEGR1N) must use two distinct codelists of the correct types. |
| HRL-CL-020 | `engines/herald/HRL-CL-020.yaml` (new) | When `Origin = Predecessor`, row's Codelist must equal the source variable's Codelist. |
| HRL-CL-021 | `engines/herald/HRL-CL-021.yaml` (new) | Any non-empty `Codelist` reference on Variables sheet must exist as an ID on the Codelists sheet. |

Master CSV, configs, manifest, CHANGELOG, README, and CLAUDE.md rule-count
references have been updated in heraldrules to match. The herald engine
count went from 256 → 260.

## Part B — Herald R package changes required to implement Part A

### B.1 — `R/val-checks.R`

**Extend `check_codelist()`** (around original lines 255-339) to emit
HRL-CL-002 before the existing HRL-CL-001 value check. Add a small helper
`.types_compatible()` that normalises "text/character/char/string" to
"char" and "integer/float/numeric/int/decimal" to "num" and compares
buckets.

**Add three new functions** (all operate on `var_spec` + `codelist` only
— they do not need dataset values):
- `check_paired_codelists(var_spec, codelist)` → HRL-CL-010 findings
- `check_predecessor_codelist(var_spec)` → HRL-CL-020 findings
- `check_codelist_id_exists(var_spec, codelist)` → HRL-CL-021 findings

**Add four entries** to `herald_rule_descriptions()` (HRL-CL-002, -010,
-020, -021) and narrow the HRL-CL-001 description to the value-not-in-terms
case.

### B.2 — `R/val-engine.R`

- Add `"codelist_spec"` to `.all_spec_checks`.
- Right after the existing `"consistency"` cross-dataset block in
  `validate_datasets()`, call the three spec-only checks once
  (not per-dataset):
  ```r
  if (!is.null(spec) && "codelist_spec" %in% active_checks) {
    findings_list <- c(
      findings_list,
      check_codelist_id_exists(spec$var_spec, spec$codelist),
      check_paired_codelists(spec$var_spec, spec$codelist),
      check_predecessor_codelist(spec$var_spec)
    )
  }
  ```
- Update `@section Rule IDs` and `@param ignore_spec_checks` in the
  `validate()` roxygen header.

### B.3 — Tests

Add `tests/testthat/test-val-checks-codelist.R` with positive + negative
+ edge cases for each of the four checks, and a snapshot assertion that
`herald_rule_descriptions()` names HRL-CL-001/002/010/020/021.

### B.4 — Non-ASCII guard

Every message string and roxygen comment must stay ASCII (R CMD check
WARNs otherwise). Use plain `--` rather than em-dashes.

## Part C — Independent improvements to the validation report

These are orthogonal to the rules and were produced in response to
user feedback during the same session. They belong to herald, not
heraldrules.

### C.1 — Rules tab aggregation (originally "Finding E")

`val-report.R:475-537` rendered the Rules tab with
`msg <- htmlesc(rf$message[1L])`, so a rule firing across N distinct
codelists showed only the first sample message and no hint of
multi-variant behaviour.

Required changes to `val-report.R`:
- Add a **Variables** column next to Datasets in the Rules tab (HTML).
  Value: `paste(unique(rf$variable), collapse=", ")`.
- Replace the single-message cell with: if
  `length(unique(rf$message)) > 1`, render
  `"<N> variants -- e.g. <first>"`; otherwise render the single message.
- Mirror into the XLSX Rules sheet (Rule_ID / Impact / Source / Count /
  Datasets / Variables / Message / Description). Update the `col_widths`
  vector to match (8 entries).
- In the JSON export, optionally add `message_variants`, `datasets`, and
  `variables` fields alongside `message` for each rule entry.

Update the corresponding `<thead>` in `inst/templates/report.html` to
add the Variables column.

### C.2 — Issues tab row-range compaction (originally "Option F")

The Issues tab emitted one HTML row per finding, so a rule firing on 74
rows produced 74 visually identical cards. Collapse near-duplicates.

Required changes to `val-report.R`:
- Add a private helper `.compact_rows(rows, max_ranges = 20L)` that turns
  `c(1:222, 225, 229:300)` into `"1:222, 225, 229:300"`. Handles
  empty / NA / singleton / run / scattered / cap-with-"+N more" cases.
- Add a private helper `.group_findings_by_identity(findings)` that
  groups by `(rule_id, impact, dataset, variable, value, message,
  expected)` while preserving first-seen order.
- Rewrite the Issues loop around `val-report.R:268-354`: iterate groups
  instead of individual findings; `Row` cell uses `.compact_rows()`;
  add a `Count` cell.
- Update `inst/templates/report.html` Issues-tab `<thead>`: rename
  **Row** → **Rows**, insert a **Count** column. Total column count
  becomes 9.
- Mirror the grouping into the XLSX **Issues** sheet (the flat
  **Issue Details** sheet stays one-per-finding on purpose for users
  who want raw rows).

### C.3 — Tests

Extend `tests/testthat/test-val-report.R` with unit tests for both new
helpers and one snapshot assertion that the HTML Issues tab emits a
compacted range like `>1:10<` when a rule fires on contiguous rows.

## Verification checklist (to run in the herald session)

1. `Rscript -e "devtools::document()"`
2. `Rscript -e "devtools::test()"` — expect > 3100 PASS, 0 FAIL.
3. `Rscript -e "devtools::check(document = FALSE, manual = FALSE, vignettes = FALSE)"` —
   expect 0 errors / 0 warnings / 0 notes.
4. Optional manual smoke: point the harness at
   `~/projects/r/own-tests/herald/buildspec-test/output/HBPD03_spec.xlsx`
   (pre-fix state from git history); confirm HRL-CL-002 fires on AGEGR1,
   HRL-CL-010 on AGEGR1/AGEGR1N, HRL-CL-020 on the 32 Predecessor rows,
   HRL-CL-021 on the three stray codelist refs.

## Working-tree snapshot (what this session already wrote to herald)

```
 M R/val-checks.R
 M R/val-engine.R
 M R/val-report.R
 M inst/templates/report.html
 M man/validate.Rd
 M tests/testthat/test-val-report.R
?? tests/testthat/test-val-checks-codelist.R
```

All the above changes have passed:
- `devtools::test()`: 3191 PASS / 0 FAIL / 3 SKIP.
- `devtools::check()`: 0 errors / 0 warnings / 0 notes.

The herald session can choose to keep these edits (review + commit) or
revert and re-apply from this document. Going forward, any new rule
that requires matching R code must land via this handover flow, not via
direct edits from the heraldrules session.
