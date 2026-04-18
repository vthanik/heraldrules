# Handover to Herald R Package -- 2026-04-18 session (Phase 1: Beat P21)

**From:** `heraldrules` Phase 1 of the "Beat Pinnacle 21 Community" program.
**To:** a Claude Code session opened inside `/Users/vignesh/projects/r/herald/`.
**Supersedes:** none. Orthogonal to `HANDOFF_TO_HERALD.md` (2026-04-17 HRL-CL work).
**Plan of record:** `/Users/vignesh/.claude/plans/plan-are-we-focusing-wobbly-stallman.md`.

## Why this handover exists

A test run of `/Users/vignesh/projects/r/own-tests/herald/api-usage/examples/05_end_to_end.R`
produced a P21 report with two major findings (AD0047 required-variable
absences on ADAE; AD0124 PARCAT1-within-PARAMCD inconsistency on ADVS)
that herald did not reproduce against the same data.

Root cause is *not* missing rule coverage. Both rules exist as YAMLs in
`engines/pmda/`. The actual root causes are:

1. `R/rule-execute.R:164-166` skips only `executability == "Not Executable"`.
   Rules with `executability %in% c("Reference", "Partially Executable", ...)`
   run anyway, stub `check:` blocks return zero findings, and the user sees
   a misleadingly clean report.
2. Herald's `required_variables` operator at `R/rule-operator.R:862` is a
   no-op stub returning `rep(FALSE, length(x))`.
3. AD0124 needed a working `not_consistent_within` binding, which exists at
   `R/rule-operator.R:833` but the YAML shipped with a placeholder
   `__variable__` name.

Phase 1 has fixed item 3 on the heraldrules side (AD0124 is now
Fully Executable with CDISCPILOT01 tests). Items 1 and 2 are engine bugs
and must be fixed in this session. Additionally a larger operator-library
expansion unlocks ~163 more rules and is documented in section 4.

After this handover lands, re-running `05_end_to_end.R` should reproduce:
- AD0124: ~1,210 findings on ADVS.
- AD0047: ~8 findings on ADAE (blocks on section 3).

---

## 1. Engine honesty fix (blocking, highest priority)

### The bug

`R/rule-execute.R:164-166`:

```r
if (identical(rule$executability, "Not Executable")) {
  return(empty_findings())
}
```

Every other executability value (`Reference`, `Partially Executable`,
`Partially Executable - Possible Overreporting`, `Partially Executable -
Possible Underreporting`) falls through to rule execution. Many of those
rules ship stub `check:` blocks (e.g. `check: []`) and return zero
findings silently.

### The fix

Replace with an allow-list of genuinely runnable states. Phase 2b-prep
(2026-04-18 update) confirmed that 654 of 656 catalog "Partially
Executable" rules ship with real `check:` blocks — not stubs. Only 2
true stubs remain (ADaM-047, AD0256), both now rewritten as Reference.
So Partially Executable variants belong in the runnable list:

```r
runnable <- c(
  "Fully Executable",
  "Hardcoded",
  "Partially Executable",
  "Partially Executable - Possible Overreporting",
  "Partially Executable - Possible Underreporting"
)
if (!isTRUE(rule$executability %in% runnable)) {
  return(empty_findings(
    skipped = TRUE,
    skip_reason = rule$executability %||% "unspecified"
  ))
}
```

`empty_findings()` needs two optional parameters (`skipped = FALSE`,
`skip_reason = NA_character_`) so `validate()` can aggregate skip reasons.

The engine should also stamp findings with a `coverage_caveat` attribute
when the source rule is `Partially Executable*`, so the summary/report
layer can flag "known undercoverage" or "possible overreporting" rules
alongside full findings. This keeps users informed without hiding real
hits.

### Tests

- `tests/testthat/test-rule-execute.R`: a synthetic rule with
  `executability: Reference` must return zero findings AND record a skip.
- Same file: a `Fully Executable` rule with a valid `check:` block must run.
- Snapshot test: `empty_findings()` output shape is stable.

### Acceptance

`grepl("Reference", rule$executability)` scenarios short-circuit without
running the `check:` block at all. Confirmed by adding a print side
effect temporarily inside any operator; that print must not fire when
the rule is Reference.

---

## 2. Skipped-rule summary emission (blocking)

### Where

- `R/val-engine.R` around `new_herald_validation()` (line 475).
- `R/val-class.R:88-95` where `$summary` is computed.

### What

Every `validate()` call must tell the user how many rules actually ran
vs. how many were skipped. Current behaviour silently omits this; users
cannot distinguish "catalog has no applicable rule" from "applicable rule
exists but is Reference".

Additions to the findings object returned by `validate()`:

- `executed_count` (integer).
- `skipped_count` (integer).
- `skipped` tibble with columns `rule_id`, `standard`, `executability`, `reason`.

At end of `validate()`:

```r
rlang::inform(c(
  sprintf(
    "Executed %d rules. Skipped %d (Reference or unsupported).",
    executed_count, skipped_count
  ),
  i = "See `result$validation$skipped` for details."
))
```

Extend `summary.herald_validation` to print breakdown by `standard`:
`executed / skipped / total`.

### Tests

- Snapshot of the `inform()` banner on a mixed-executability fixture.
- `executed_count + skipped_count` invariant against the config's rule count.

---

## 3. Implement `required_variables` (unblocks AD0047 + ~80 similar rules)

### Where

`R/rule-operator.R:862` -- replace the no-op stub.

### YAML usage

```yaml
check:
  all:
    - name: __dataset__
      operator: required_variables
      value:
        domain: ADAE
        ig_version: "ADaM-IG 1.1"
```

Sentinel name `__dataset__` means "this is a dataset-level check, not a
per-row check". Engine must recognise this (likely an existing pattern
for dataset-level operators -- if not, add a check in `rule-execute.R`
that routes dataset-level rules separately).

### Semantics

Look up the Required-column list for `domain` + `ig_version`, compare
against the dataset's column names, emit one finding per missing
required column (not per row; `sensitivity: Dataset`).

### Required-variable source

Package ships `inst/extdata/adam-required-vars.rds`:

```r
list(
  `ADaM-IG 1.1` = list(
    ADSL  = c("STUDYID", "USUBJID", "SUBJID", "SITEID", "AGE", "AGEU",
              "SEX", "RACE", "ETHNIC", "ITTFL", ...),
    ADAE  = c("STUDYID", "USUBJID", "AETERM", "AEBODSYS", "AEDECOD",
              "AESEV", "AESER", "AESTDTC", ...),
    BDS   = c("STUDYID", "USUBJID", "PARAMCD", "PARAM", "AVAL", "AVALC",
              "ADT", "ADY", "VISIT", ...),
    OCCDS = c("STUDYID", "USUBJID", ...)
  ),
  `ADaM-IG 1.2` = list( ... )
)
```

Source material:
- ADaM IG 1.1 sections 3.2 (ADSL), 4.2 (BDS), OCCDS appendix.
- ADaM IG 1.2 sections 3.2, 4.2, OCCDS appendix.
- ADaM AE IG v1.0 (ADAE).

### Tests

- Positive: CDISCPILOT01 ADAE with all required columns -> 0 findings.
- Negative: CDISCPILOT01 ADAE with AESEV stripped -> 1 finding with
  `variable = "AESEV"` and message "AESEV is required but not present".

### After this lands (heraldrules side)

Flip `engines/pmda/AD0047.yaml` to `executability: Fully Executable`, add
the YAML check block shown above, add positive/negative tests, re-run
the heraldrules rebuild/validate pipeline.

---

## 4. New operators to unlock ~163 additional rules

Non-blocking, but the faster these ship the faster the heraldrules
Phase 4 batch authoring can begin. Prioritise by rule-count unlock.

### 4a. Trivial single-row operators (ship first)

| Operator | Body | Unlocks |
|---|---|---|
| `paired_suffix_date_order` | for any `*SDT`/`*EDT` pair, flag row where SDT > EDT when both populated | AD0792 |
| `paired_suffix_time_order` | same, `*STM`/`*ETM` | AD0793 |
| `paired_suffix_datetime_order` | same, `*SDTM`/`*EDTM` | AD0794 |
| `dataset_filesize` | flag when `file.size(xpt_path)` > `value` (bytes) | SD1071 |

### 4b. Single-row pattern operators (unlock 75 rules)

| Operator | Violates when | Est. rules |
|---|---|---|
| `is_complete_date` | partial ISO date (YYYY-only, YYYY-MM) when full required | 16 |
| `in_codelist` | value not in named NCI codelist (lookup via `herald-controlled-terminology.csv`) | 18 |
| `in_range` | numeric value outside `[min, max]` inclusive | 15 |
| `matches_iso_duration` | not a valid ISO 8601 duration | 3 |
| `valid_iso_8601_datetime` | not a valid ISO 8601 datetime | 3 |
| `date_precedes_or_equals` | date1 > date2 | 5 |
| `datetime_precedes_or_equals` | datetime1 > datetime2 | 3 |
| `not_equal_to_variable_ci` | case-insensitive variant | 8 |
| (plus 13 smaller; per-rule signatures documented in heraldrules as rules author them) | -- | -- |

### 4c. Group/aggregate operators (unlock 19 rules)

| Operator | Semantics |
|---|---|
| `distinct` | flag rows that duplicate on the named key tuple |
| `is_not_unique_relationship` | directional opposite of `not_consistent_within` |
| `sequential_present` | `__TRTxxP__`-style variable naming must have no gaps |
| `not_consistent_with_variable` | grouping specified by variable reference, not literal column name |

### 4d. Nested group (unlocks AD0895)

| Operator | Semantics |
|---|---|
| `not_consistent_within_pair` | flag rows where `value1` is inconsistent within `(PARAMCD, value2)` pairs -- needed for AVALC->AVALCATy and BASEC->BASECATy nested groupings |

### 4e. Cross-dataset (unlocks HRL-AD-009 and future population-flag work)

| Operator | Semantics |
|---|---|
| `consistent_population` | YAML value = `list(reference_dataset = "ADSL", reference_var = "USUBJID", flag_var = "SAFFL", flag_value = "Y")` -- flag rows whose USUBJID is not in the filtered subset of the reference dataset |

### 4f. Metadata/spec (unlock ~68 CT rules)

| Operator | Semantics |
|---|---|
| `check_value` | evaluate regex or enumeration against a define.xml / CT metadata path |
| `codelist_code_match` | variable's value must correspond to a term in `value.codelist` (uses `herald-controlled-terminology.csv`) |

### 4g. Spec-level operators for the HRL-MD family (unlock 19 rules)

Phase 2a rewrote 21 HRL-MD rules to Fully Executable with existing
operators and deprecated 40 HRL-FM duplicates. The remaining 19 HRL-MD
rules (004, 013, 015, 018-022, 025, 027, 028, 030, 031, 033-038) need
the following new operators. Each rule's YAML `notes:` field cites the
exact subsection below.

| Operator | Semantics | Unlocks |
|---|---|---|
| `valid_codelist_id` | codelist reference on Variables/Terms sheet exists as an ID on the Codelists sheet | MD-004, MD-021, MD-030 |
| `valid_codelist_term` | term is a member of the referenced codelist's term list | MD-031 |
| `valid_form_id` | form reference on Questions/Sections sheet exists as a FormDef element | MD-013, MD-025 |
| `valid_section_id` | section reference on Questions sheet exists as an ItemGroup element | MD-015 |
| `valid_measurement_unit` | unit reference on Questions sheet exists on the Units tab | MD-022 |
| `valid_sdtm_target_variable` | SDTM Target column references a variable that exists in the target SDTM domain | MD-033, MD-034 |
| `conditional_empty_when` | field is empty when trigger field not in specified set | MD-018 |
| `conditional_required_when` | field populated when trigger field in specified set | MD-019 |
| `conditional_regex_when` | field matches regex when populated | MD-020 |
| `child_count_gte` | parent row has >= N child rows on a named child sheet (Events->Forms, Forms->Sections, Sections->Questions, Codelists->Terms) | MD-035, MD-036, MD-037, MD-038 |
| `length_le_within_group` | Terms of codelists in a specified parent group have Term length <= N chars | MD-027, MD-028 |

These operators need a broader change too: herald's YAML-rule runner today
assumes `name:` is a dataset column. For spec-level rules it must route
the rule to the spec sheet (Codelists / Terms / Forms / Sections / Questions / Units / Variables)
named by the rule's `category: Specification Metadata` tag. Practical design:

1. Engine reads the category. If `Specification Metadata`, route to the
   appropriate spec-data-frame (already parsed via `read_spec()`).
2. `name:` refers to a spec-sheet column (e.g. `codelist_name`, `data_type`,
   `order`) rather than a dataset column.
3. Existing spec-handling code lives in `R/val-checks.R` (hardcoded HRL-CL/VAR/TYP
   checks); the YAML route should converge on the same data structures.

Once that routing exists, the 21 already-promoted HRL-MD rules can be
verified end-to-end against real spec sheets. Until then, their tests
run through the placeholder dataset pattern used by the existing HRL-DD
executable set.

### 4h. ODM XML validation operators (unlock HRL-OD-001..009)

Herald's ODM v1.2 validation rules operate on the raw ODM XML file,
not on record data. They need a dedicated XML-reading layer plus a
small set of operators:

| Operator | Semantics | Unlocks |
|---|---|---|
| `xml_namespace_equals` | root element's `xmlns` equals the expected URI | HRL-OD-001 |
| `xml_attribute_required` | named attribute is present and non-empty at every element matching an XPath | HRL-OD-002 |
| `xml_element_required` | named child element is present at every element matching an XPath | HRL-OD-003 |
| `xml_element_unique` | element of a named tag appears at most once under a parent XPath | HRL-OD-004 |
| `xml_typed_value_pattern` | attribute/element text value matches the regex declared by its ODM `DataType` | HRL-OD-005, -006, -007, -008, -009 |

Engine plumbing needed:
- New input path on `validate()` for `odm = "path/to/odm.xml"`.
- XML parsed with `xml2::read_xml()` once, cached on the findings object.
- Each rule's YAML `check:` block uses `name:` as the XPath expression
  (e.g. `name: "//StudyEventDef"`).
- Operators receive the parsed XML node set, not a vector of values.

The 5 `xml_typed_value_pattern` uses share a regex table; the patterns
for float / date / time / sasName / fileName are specified in the ODM
1.2 XSD and should be embedded once in `inst/extdata/odm-patterns.rds`.

### 4i. ARM metadata operators for Define-XML (unlock HRL-DD-008..014)

Analysis Results Metadata (ARM) lives inside `define.xml` as
`<arm:AnalysisResultDisplays>`. These 7 rules enforce uniqueness,
required-child, and BDS-reference invariants on ARM elements:

| Operator | Semantics | Unlocks |
|---|---|---|
| `arm_absent_in_non_adam_define` | SDTM/SEND define.xml must not contain arm:AnalysisResultDisplays | HRL-DD-008 |
| `arm_oid_unique` | arm:ResultDisplay OID unique within arm:AnalysisResultDisplays | HRL-DD-009 |
| `arm_name_unique` | arm:ResultDisplay Name unique | HRL-DD-010 |
| `arm_description_required` | each arm:ResultDisplay has a Description child | HRL-DD-011 |
| `arm_analysisresult_oid_unique` | arm:AnalysisResult OID unique within a arm:ResultDisplay | HRL-DD-012 |
| `arm_parameter_oid_required_when_bds` | ParameterOID required when arm:AnalysisResult references BDS datasets | HRL-DD-013 |
| `arm_parameter_oid_references_paramcd` | when ParameterOID is present, at least one AnalysisDataset must be BDS and ParameterOID must reference a PARAMCD variable in that dataset | HRL-DD-014 |

All 7 operate on the parsed `define.xml` tree. Reuse the XPath/xml2
infrastructure introduced in section 4h, gated by the `arm:`
namespace.

### Summary of new operators across section 4

| Section | Count | Rules unlocked |
|---|---:|---:|
| 4a Trivial single-row | 4 | 4 |
| 4b Single-row pattern | 21 | 75 |
| 4c Group/aggregate | 4 | 19 |
| 4d Nested group | 1 | 1 |
| 4e Cross-dataset | 1 | 1 + AD0256 |
| 4f Metadata/CT | 2 | ~68 |
| 4g Spec-level (HRL-MD) | 11 | 19 + HRL-DD-001..007, HRL-DD-109 |
| 4h ODM XML | 5 | 9 (HRL-OD-001..009) |
| 4i ARM metadata | 7 | 7 (HRL-DD-008..014) |
| **Total** | **56** | **~230** |

Once every operator in section 4 ships, herald's runnable-rule count
climbs from 3,700 to ~3,800 of 3,878 YAMLs (~98%). The residual ~80
rules are deprecated duplicates (40 HRL-FM) and genuinely-guidance FDA
Business Rules (86) that are Reference by nature and do not admit
mechanical checks.

### 4j. Catalog-referenced operators missing from `rule-operator.R`

Phase 2d audit compared every operator name appearing in catalog YAML
`check:` blocks against the 164 operators defined in
`../herald/R/rule-operator.R`. Four name-aliases were resolved in the
catalog side (`not_empty` -> `non_empty`, `length_greater_than` ->
`longer_than`, `length_match` -> `has_equal_length`, `not_unique` ->
`is_unique_set`). The following 12 operator names are still referenced
by catalog YAMLs but are absent from herald's registry. Until herald
adds them, any rule using these operators fails silently at runtime.

| Operator | Uses | Sample rule IDs | Semantics required |
|---|---:|---|---|
| `not_within_tolerance_of_formula` | 19 | ADaM-131, ADaM-223, AD0223, AD0225 | **Important.** Likely a polarity error -- herald has `within_tolerance_of_formula` which already flags when the formula is violated. These 19 rules should either be renamed to `within_tolerance_of_formula` (if pre-conditions are inverted too) or herald should add a genuine `not_within_tolerance_of_formula` alias. Needs a focused polarity-audit session similar to the 2025-04 HRL-SD/TS fix (see CLAUDE.md). |
| `not_consistent_with_variable` | 15 | ADaM-092-SD through ADaM-095-SD | Same as `not_consistent_within` but grouping is a variable reference, not a literal column name. Merge with HANDOFF §4c. |
| `not_character` | 8 | ADaM-1027..1035 (v1.2 type-assertion rules) | Type-check: flag when `x` is not character. |
| `less_than_variable` | 5 | ADaM-084, ADaM-099-SD, ADaM-121 | Cross-column: flag when `x >= value_col`. Cousin of `not_equal_to_variable` which already exists. |
| `label_match` | 2 | HRL-AD-001, HRL-AD-006 | Variable label comparison across SDTM<->ADaM. Needs spec access (variable metadata). |
| `format_match` | 2 | HRL-AD-002, HRL-AD-007 | Variable format comparison across SDTM<->ADaM. Needs spec access. |
| `no_matching_record` | 2 | HRL-SD-012, HRL-SD-013 | Cross-dataset: flag when no row matches the join key. Cousin of HANDOFF §4e `consistent_population`. |
| `not_numeric` | 2 | ADaM-1027, ADaM-1030 | Type-check: flag when `x` is not coercible to numeric. |
| `type_match` | 2 | HRL-AD-013, HRL-AD-014 | Variable type comparison across SDTM<->ADaM. Needs spec access. |
| `adsl_consistency_check` | 1 | ADaM-1046 | ADSL-level dataset consistency assertion; likely a wrapper over several sub-checks. Needs a narrower spec. |
| `exists_in_dataset` | 1 | HRL-AD-021 | Cross-dataset existence: flag when `x` is not present in the reference dataset. Subset of §4e `consistent_population`. |
| `not_in_define_vlm` | 1 | HRL-DD-015 | Define.xml VLM cross-reference. Merge with §4g. |

Recommended implementation order for §4j:

1. `not_character`, `not_numeric` (trivial; 10 rules unlocked together).
2. `less_than_variable` (cousin of existing `not_equal_to_variable`).
3. `not_consistent_with_variable` (cousin of existing `not_consistent_within`; 15 rules).
4. `no_matching_record`, `exists_in_dataset` -- resolve together with §4e.
5. `label_match`, `format_match`, `type_match` -- resolve together with §4g spec-metadata routing.
6. `adsl_consistency_check` -- narrow-spec needed; may become multiple finer checks.
7. `not_within_tolerance_of_formula` (19 rules) -- schedule a polarity-audit session; either rename YAMLs to `within_tolerance_of_formula` or ship the negative form as a true alias.

These 12 operators added to the 56 already specified in sections 4a-i
bring the total to **68 new operators** unlocking **~260 additional
rules** and moving runnable coverage to ~98% of the catalog.

---

## 5. Regression fixtures

Add `tests/testthat/fixtures/p21-parity/`:

- `adae-required-missing.rds` -- CDISCPILOT01 ADAE minus AESEV.
- `advs-parcat1-inconsistent.rds` -- CDISCPILOT01 ADVS with one PARAMCD
  having two distinct PARCAT1 values.
- `expected-findings.csv` -- expected rule_id + count pairs per fixture.

Hook into `tests/testthat/test-p21-parity.R`. These become the regression
floor for the P21-parity program. Any engine change that breaks them
should fail CI.

---

## 6. Verification loop after each section lands

Per global CLAUDE.md:

1. `Rscript -e "devtools::document()"`
2. `Rscript -e "devtools::test()"` -- all green.
3. `Rscript -e "devtools::check()"` -- 0 errors / 0 warnings / 0 notes.
4. Run `05_end_to_end.R`:
   - After section 1: banner prints "Executed N, Skipped M" with M > 0.
   - After heraldrules AD0124 rebuild (already done this session): findings
     include ~1,210 AD0124 hits on ADVS.
   - After section 3 + heraldrules AD0047 flip (subsequent heraldrules session):
     findings include ~8 AD0047 hits on ADAE.

---

## 7. What stays with heraldrules (do NOT do in herald session)

The herald session owns R code. heraldrules owns YAML + CSV + configs + docs.
The following items land in a future heraldrules session, NOT here:

- Flip AD0047 back to Fully Executable after section 3 lands.
- Add real `check:` blocks + tests to AD0792 / AD0793 / AD0794 / AD0895 /
  SD1071 once their operators land (sections 4a, 4d, 4f).
- Catalog-wide stub purge (~1,400 YAMLs still Reference).
- Author the ~864 "Bucket A" rules already expressible with existing operators.
- Build `inst/benchmarks/p21-parity/` harness.

---

## 8. Summary of what the heraldrules Phase 1 commit already shipped

- `engines/pmda/AD0124.yaml` -- Fully Executable, uses `not_consistent_within`,
  positive + negative CDISCPILOT01 tests.
- `engines/pmda/AD0047.yaml` -- clean Reference (no `check:` block), notes
  field points here.
- `engines/pmda/AD0792.yaml`, `AD0793.yaml`, `AD0794.yaml`, `AD0895.yaml`
  -- 4 new clean Reference YAMLs for P21 ADaM IDs genuinely absent from
  all upstream sources. SD1071 and AD2001 excluded (SD1071 already ships
  via FDA; AD2001 excluded by user request).
- `CLAUDE.md` -- new "No stubs" invariant + phased-program summary.
- `README.md` -- Runnable/Total breakdown per engine.
- `CHANGELOG.md` -- Phase 1 entry.
- `inst/scripts/build-master-csv.R` -- `runnable` column (derived from
  `executability`).
- `inst/scripts/build-manifest.R` -- `executable_count` per engine.
- `herald-master-rules.csv`, `manifest.json`, `configs/*.json` -- regenerated.

No version-field bumps anywhere (pre-CRAN rule in CLAUDE.md).

---

## 9. Contact points between the two repos

| heraldrules artifact | herald artifact it constrains |
|---|---|
| `engines/*/*.yaml` `check:` blocks | `R/rule-execute.R`, `R/rule-operator.R` |
| `ct/*.json` + `herald-controlled-terminology.csv` | `in_codelist`, `codelist_code_match` operators |
| `configs/*.json` | rule set assembly in `validate()` |
| `manifest.json` / `herald-master-rules.csv` `runnable` column | `executable_rule_count()` helper, `summary()` output |
| `inst/extdata/adam-required-vars.rds` (herald-owned) | `required_variables` operator data source |

If a herald change requires a schema tweak in heraldrules, write a
`HANDOFF_TO_HERALDRULES.md` in the herald repo root so the next
heraldrules session picks it up.
