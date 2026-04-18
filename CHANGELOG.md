# Changelog

All notable changes to herald-rules are documented in this file.

Versions follow the format `v{YYYY}.{Q}` aligned with NCI EVS
Controlled Terminology quarterly releases. See [GOVERNANCE.md](GOVERNANCE.md)
for release cadence details.

---

## Unreleased

### Beat P21 — Phase 2e (2026-04-18, polarity audit)

#### Fixed

Resolved the polarity bugs flagged by Phase 2d. The Phase 2d audit
identified that many rules treated `check:` as a violation template
rather than a passing template, inverting operators. Per CLAUDE.md
passing-condition convention: operator names describe **valid**
state, operator bodies return TRUE when data **violates** that state.
Under this convention:

- IF-populated pre-conditions use `empty` (flags when populated);
- `non_empty` flags when empty; `equal_to X` flags when NOT X.

**Tolerance-formula rules (19):** CHG/PCHG/ratio calculation rules
across `engines/pmda/` and `engines/cdisc/` used the nonexistent
`not_within_tolerance_of_formula` operator and inverted pre-conditions.
Fixed:
- `non_empty` → `empty` on IF-populated pre-conditions (e.g. CHG
  populated, AVAL populated, BASE populated).
- `not_within_tolerance_of_formula` → `within_tolerance_of_formula`
  (which already exists in herald and correctly flags when the
  formula is violated).
- `not_equal_to 0` → `equal_to 0` on BASE/denominator guards
  (IF-`!= 0` pre-condition -- `equal_to 0` flags when BASE != 0, which
  IS the pre-condition firing as intended).

Affected files: AD0131, AD0132, AD0133, AD0134, AD0223, AD0225,
AD0582, AD0586 (PMDA) and ADaM-131, -131-SD, -132, -132-SD, -133,
-133-SD, -134, -134-SD, -223, -225, -582, -586 (CDISC).

**HRL-DD spec-exists rules (20):** The `non_empty ID + equal_to
__computed` pattern was inverted across 20 rules that check
cross-references in the spec (dataset exists, codelist_id exists,
method_id exists, comment_id exists, etc.). Fixed with a paired
swap: operators `non_empty` <-> `empty` AND values `true` <-> `false`
so that (ID populated) AND (reference target missing) fires the
violation.

Affected: HRL-DD-063, -067, -078, -082, -085, -086, -087, -088,
-089, -090, -091, -092, -093, -094, -095, -096, -101, -103, -104,
-106.

**HRL-DD IF-populated/THEN-empty rules (3):** HRL-DD-031, -075, -076
used `non_empty + empty` (intent: IF X populated AND Y empty, flag).
Swapped to `empty + non_empty` per the convention.

**HRL-DD-077:** Manually corrected -- `empty + equal_to true` to
`non_empty + equal_to false` (semantic: flag when decoded_value
empty AND codelist uses CodeListItem format).

**Total: 43 rules fixed.** All three validators pass. Catalog
runnable count unchanged (3,700) because these rules were already
marked runnable; they were previously producing incorrect findings
(likely zero findings on real data) and now produce the correct set.

#### Ongoing

- HRL-DD rules using other operator patterns (`not_equal_to+empty`,
  `equal_to+not_in`, etc.) were not audited in this pass. A follow-up
  session should inspect each remaining pattern group (totals in
  CLAUDE.md "Known open polarity issues").

### Beat P21 — Phase 2d (2026-04-18, operator audit)

#### Fixed

- Catalog audit compared every operator name referenced in YAML
  `check:` blocks against the 164 operators defined in
  `../herald/R/rule-operator.R`. Four name aliases were renamed in the
  catalog (each semantically equivalent under the passing-convention):
  - `not_empty` → `non_empty`: 31 replacements across 29 HRL-DD rules.
  - `length_greater_than` → `longer_than`: 2 CDISC rules (ADaM-017, -017-SD).
  - `length_match` → `has_equal_length`: 2 HRL-AD rules.
  - `not_unique` → `is_unique_set`: 1 HRL-DD rule (DD-072).
- `tests/allowed-operators.txt` extended with the newly-used operator
  names (`longer_than`, `has_equal_length`, `has_different_length`,
  `is_unique_set`, `is_not_unique_set`).

#### Deferred (documented in HANDOFF §4j)

- 12 operator names are still referenced by catalog YAMLs but are
  absent from herald's registry. They are enumerated with
  usage counts, sample rule IDs, and a recommended implementation
  order in `HANDOFF_TO_HERALD_2026-04-18.md` section 4j. Highest-impact
  item: `not_within_tolerance_of_formula` (19 rules; likely polarity
  error — the intended semantic is already covered by herald's
  `within_tolerance_of_formula`).
- `CLAUDE.md` "Known open polarity issues (2026-04)" section added,
  flagging a suspected HRL-DD-wide polarity bug similar to the 2025-04
  HRL-SD/TS fix (HRL-DD-031 currently uses `non_empty` as an
  IF-populated pre-condition which is inverted per the CLAUDE.md
  passing-condition convention).

Total new operators now requested from herald across HANDOFF §4a–4j:
**68 operators unlocking ~260 additional rules**, moving runnable
coverage from 3,700 (95%) to ~3,800 (~98%) once all land.

### Beat P21 — Phase 6 (2026-04-18)

#### Added

- **`inst/benchmarks/p21-parity/`** — regression harness proving that
  herald + herald-rules reproduce the findings Pinnacle 21 Community
  would emit on curated data. Ships with:
  - 5 CSV fixtures under `fixtures/` (ADVS PARCAT1 inconsistent/consistent,
    ADAE required-var missing/complete, LB LBSTRESU inconsistent).
  - `expected-findings.csv` -- truth table with columns `fixture`,
    `domain`, `rule_id`, `expected_count`, `status`, `blocked_on`, `notes`.
  - `run-benchmark.R` -- loads fixtures, calls `herald::validate()`,
    diffs actual to expected, exits non-zero on mismatch. Distinguishes
    "blocked on herald operator" (visible SKIP lines) from "executed
    and clean" so coverage gaps never go silent.
  - `README.md` -- contract with herald, rationale, how to add new
    fixtures, and which expectations light up first (ADAE AD0047 flips
    from blocked to PASS once HANDOFF §3's `required_variables`
    operator ships).
- Harness runs cleanly in diagnostic mode when `herald` is not
  installed, making it useful for catalog-side sanity checks without
  requiring a full dev-environment.

### Beat P21 — Phase 2c (2026-04-18)

#### Changed

- **25 un-annotated herald Reference rules** now carry specific
  `notes:` fields citing the exact herald operator each blocks on:
  - HRL-OD-001..009 (9 rules) — `xml_namespace_equals`,
    `xml_attribute_required`, `xml_element_required`,
    `xml_element_unique`, `xml_typed_value_pattern` (HANDOFF §4h).
  - HRL-SD-002 (1 rule) — `dataset_filesize` (HANDOFF §4a).
  - HRL-DD-001..007 (7 rules) — define.xml attribute-length / Assigned
    Value / Codelist / Where Clause / paired-terms operators (HANDOFF §4g).
  - HRL-DD-008..014 (7 rules) — ARM metadata uniqueness /
    required-child / ParameterOID operators (HANDOFF §4i).
  - HRL-DD-109 (1 rule) — schema-version-aware `in` pre-condition
    (HANDOFF §4g).
- **HANDOFF_TO_HERALD_2026-04-18.md** gains two new subsections:
  §4h (5 XML operators for ODM validation) and §4i (7 ARM metadata
  operators). Section 4 summary table now reconciles 56 new operators
  unlocking ~230 rules — after which herald runs ~98% of the catalog.

#### Fixed

- **84 Reference rules** carried `check: []` stubs (40 deprecated
  HRL-FM, 19 blocked HRL-MD, 25 newly-annotated HRL-OD/SD/DD).
  Stripped per the "No Stubs" invariant. Reference rules now uniformly
  omit the `check:` key.
- **`tests/validate-define-rules.R`** check-1 required-fields list now
  distinguishes executable (must have `check:`) from Reference
  (must NOT have `check:`). Aligns the validator with the invariant.

### Beat P21 — Phase 2b (2026-04-18)

#### Fixed

- **86 FDA Business Rules v1.5** YAMLs under `engines/fda/` lacked an
  `Executability:` field and carried a `Check: []` stub. Added
  `Executability: Reference`; removed the stub. These are guidance-grade
  rules from FDA Study Data Technical Conformance Guide that are not
  mechanically checkable and stay Reference by nature. Brings them into
  compliance with the "No Stubs" invariant.
- **ADaM-1047** (CDISC, ADaM v1.2 SHIFTy gap-fill) had a `SHIFT1 non_empty`
  stub check that would overreport on every populated SHIFTy row.
  Converted to `Executability: Reference`, stub purged, and annotated
  with a `valid_shift_pair` operator requirement pointing to HANDOFF
  section 4b. This is the one remaining "Not Executable" entry in the
  catalog; after this fix the `Not Executable` value is no longer used.

### Beat P21 — Phase 2b-prep (2026-04-18)

#### Changed

- **Runnable allow-list expanded.** Catalog audit confirmed that 654 of
  656 "Partially Executable" rules ship with real `check:` blocks — not
  stubs. The Phase 1 strict allow-list (`Fully Executable`, `Hardcoded`
  only) was sidelining legitimate coverage. Both `inst/scripts/build-master-csv.R`
  and `inst/scripts/build-manifest.R` now treat `Partially Executable`,
  `Partially Executable - Possible Overreporting`, and
  `Partially Executable - Possible Underreporting` as runnable.
  Catalog runnable count: 3,046 → 3,700 (+654 rules, 78% → 95%).
- **`HANDOFF_TO_HERALD_2026-04-18.md` section 1** updated to match the
  expanded allow-list and to document `coverage_caveat` stamping for
  Partially-Executable findings so reports can flag known undercoverage
  or possible-overreporting rules alongside full findings.
- **`CLAUDE.md` "No Stubs" section** rewritten with the 4+1 executability
  taxonomy (Fully Executable, Hardcoded, Partially Executable, Partially
  with over/under caveat, Reference). Clarifies that Partially Executable
  is NOT a stub — it is a real check with scope caveats.

#### Fixed

- **ADaM-047 → clean Reference.** CDISC's required-variables rule had a
  stub `check: USUBJID empty` that did not match its "all required
  variables must be present" description. Rewritten to remove `check:`
  block, scope tightened to `Classes: ADSL/BDS/OCCDS`, sensitivity
  lifted to `Dataset`, and pointed at HANDOFF section 3. Mirrors the
  Phase 1 AD0047 treatment.
- **AD0256 → clean Reference.** PMDA's "USUBJID exists in ADSL"
  cross-dataset rule had the same stub. Rewritten without `check:`,
  scope `classes: [BDS, OCCDS]`, pointed at HANDOFF section 4e for
  the `consistent_population` operator.

### Beat P21 — Phase 2a (2026-04-18)

#### Deprecated

- **HRL-FM-001..040** — all 40 ADaM IG 1.1 "Form Metadata" rules
  deprecated in favor of their HRL-MD-NNN equivalents (ADaM IG 1.2
  "Metadata" namespace). Each deprecated YAML gains a `deprecated:`
  block citing `replaced_by: HRL-MD-NNN`, date 2026-04-18, and the
  reason. Files retained for audit trail.

#### Added (executable)

- **HRL-MD-001/002/003/005/006/007/008/009/010/011/012/014/016/017/023/024/026/029/032/039/040**
  (21 rules) promoted from stub `Reference` to `Fully Executable`. Each
  uses existing operators (`non_empty`, `empty`+`in`, `does_not_match_regex`)
  and ships with a positive/negative test pair following the HRL-DD
  placeholder-dataset pattern. Covers Codelist name, Event name/type,
  Repeating, Order, Mandatory, Form/Section/Question metadata, Term
  validation, and Unit required-field checks.

#### Changed

- **HRL-MD-004/013/015/018/019/020/021/022/025/027/028/030/031/033/034/035/036/037/038**
  (19 rules) gain a `notes:` field documenting the specific herald
  operator each is blocked on (e.g. `valid_codelist_id`, `valid_form_id`,
  `child_count_gte`, `conditional_empty_when`). Each note cites the
  subsection of `HANDOFF_TO_HERALD_2026-04-18.md` where the operator
  is specified.
- **Scope correction (AD0047, AD0124, AD0792, AD0793, AD0794, AD0895)**
  -- scope now uses `classes: [BDS]` / `classes: [ADSL, BDS, OCCDS]`
  rather than enumerating individual ADaM domains. Aligns with the
  `Scope.Classes` convention used by CDISC CORE rules and `read_spec`.
- **`HANDOFF_TO_HERALD_2026-04-18.md`** gains a new section 4g
  documenting the 11 spec-level operators needed to activate the 19
  still-blocked HRL-MD rules, plus the engine-side routing change
  required for YAML spec-metadata rules (category-driven dispatch to
  spec data frames instead of dataset columns).

### Beat P21 — Phase 1 (2026-04-18)

#### Added

- **AD0124** (PMDA) promoted to `executability: Fully Executable`.
  Replaces a stub `check:` block with real logic: uses the existing
  `not_consistent_within` operator on PARCAT1 grouped by PARAMCD.
  Scope extended to ADVS/ADLB/ADEG/ADQS/ADLBH/ADPC/ADPP/BDS/ADNCA/MDBDS.
  Ships with CDISCPILOT01 positive + negative tests. Resolves a gap
  surfaced by the user's P21 Community run (~1,210 findings on ADVS that
  herald was missing).
- **AD0792, AD0793, AD0794, AD0895** — four new Reference YAMLs under
  `engines/pmda/` for P21 ADaM rule IDs absent from every upstream source
  (CDISC / FDA Excel / PMDA Excel). Each includes the P21 message /
  description verbatim and an activation plan pointing to
  `HANDOFF_TO_HERALD_2026-04-18.md` section 4. AD2001 deliberately
  excluded per user request. SD1071 was NOT added — verification during
  rebuild confirmed it already ships via FDA Validator Rules v1.6
  (`engines/fda/FDAV-SD1071.yaml` + matching Excel-sourced CSV row).
- **`runnable` column** on `herald-master-rules.csv`. Derived from
  `executability`: TRUE when in the allow-list (`Fully Executable`,
  `Hardcoded`), FALSE otherwise.
- **`executable_by_engine` + `executable_engine_rules` stats** in
  `manifest.json`. Makes the runnable vs. catalogued split visible at
  the engine level.
- **`HANDOFF_TO_HERALD_2026-04-18.md`** — the engine-side work plan:
  honesty guard in `R/rule-execute.R`, `validate()` skip-summary, real
  `required_variables` operator, and the 28-operator specification that
  unlocks ~163 additional rules across Buckets B/C/D/E.

#### Changed

- **AD0047** (PMDA) rewritten as a clean Reference entry. Previous
  version had a stub `check:` (`USUBJID empty`) that did not match the
  rule's description. New version omits `check:` entirely and points at
  the handover document for activation.
- **`inst/scripts/build-master-csv.R`** — emits the new `runnable`
  column; overlays YAML `executability`/`status` on PMDA rows sourced
  from the spreadsheet; appends PMDA-directory YAMLs whose IDs are not
  in the spreadsheet (YAML is authoritative for what herald runs).
- **`inst/scripts/build-manifest.R`** — counts runnable YAMLs per engine
  by parsing `executability`; writes `executable_by_engine` and
  `executable_engine_rules` into `manifest.json`.
- **`README.md`** — overview table now shows Total / Runnable per engine;
  new "Beat Pinnacle 21" roadmap section.
- **`CLAUDE.md`** — new "No Stubs" invariant section defines the
  two-state executability model (`Fully Executable` + tests, or
  `Reference` with no `check:` block) and lists banned values. New
  "Beat Pinnacle 21" Program section documents the seven-phase plan.

#### Deprecated

- Executability values `Partially Executable`,
  `Partially Executable - Possible Overreporting`,
  `Partially Executable - Possible Underreporting`, `Not Executable`.
  Existing rules still carrying these values remain in place for now
  (Phase 2 work will sweep them); no new rule may use them. The engine
  change in `HANDOFF_TO_HERALD_2026-04-18.md` section 1 will cause any
  non-allow-list value to short-circuit with a skip record.

### Added

- **HRL-CL-002** — Codelist type mismatch between variable and referenced
  codelist. Hardcoded check in `herald::check_codelist()` that fires before the
  existing HRL-CL-001 value-in-terms scan so reviewers see a single
  "wrong codelist reference" finding instead of a flood of "value not in terms"
  errors. Motivated by HBPD03 buildspec session 2026-04-17.
- **HRL-CL-010** — Paired numeric/character variables (e.g. AGEGR1/AGEGR1N)
  must reference two distinct codelists of the correct data types (text for the
  char variable, integer for its numeric companion). New hardcoded check
  `herald::check_paired_codelists()`. Catches shared-codelist bugs directly.
- **HRL-CL-020** — Origin=Predecessor variables must inherit the source
  variable's codelist when the Predecessor column follows the "<DS>.<VAR>"
  pattern. New hardcoded check `herald::check_predecessor_codelist()`.
- **HRL-CL-021** — Any Codelist reference on the Variables sheet must exist
  as an ID on the Codelists sheet. New hardcoded check
  `herald::check_codelist_id_exists()`. Catches stray/leaked identifiers
  (Analysis Display IDs, Document IDs, typos) before they surface as
  misleading HRL-CL-001 failures. Caught AIMS0101T07STR, BPRSA118STR, OUTN
  in the HBPD03 session with zero false positives.

### Changed

- **HRL-CL-001** (version 2) — description and message narrowed to the
  "value not in Terms" failure mode only; the former "wrong codelist
  reference" case is now reported by HRL-CL-002. Rule semantics are
  backward compatible (same ID, same severity, same trigger condition).
- Herald engine rule count: 256 → 260 (HRL-CL: 1 → 5; sequence intentionally
  non-contiguous — 01x = paired-variable integrity, 02x = Origin/Predecessor
  integrity).

- **CT per-term NCI codes** — `ct/sdtm-ct.json` and `ct/adam-ct.json` now
  ship object-shaped term entries with `submissionValue`, `conceptId`, and
  `preferredTerm` per term (was plain character array). `inst/scripts/fetch-ct.R`
  rewritten to pull from CDISC Library CT packages (oldest-first walk across
  6 recent SDTM + 6 recent ADaM packages, so renamed codelists like
  RACE→RACEC are captured from older packages). `ct-manifest.json` carries
  `schema_version: 2` and `terms_format: "object"`.
- **CT deprecation metadata** — codelists present in older CT packages but
  absent from the latest one are flagged with `deprecated_in` (package name)
  and, where detectable, `superseded_by` (new submission value). Detection
  uses codelist-code match + name-prefix heuristic, plus a hand-curated
  override table at `ct/codelist-renames.json` for cases the heuristic
  can't resolve (e.g. `ETHNIC` → `ETHNICC`, where "Ethnic Group" doesn't
  prefix-match "Ethnicity As Collected"). 7 SDTM codelists flagged in the
  2026-03-27 package; 2 have explicit successors (RACE→RACEC, ETHNIC→ETHNICC).
- **Variable → codelist mapping** — new `ct/variable-to-codelist.json`
  asset built by `inst/scripts/fetch-ig-variables.R`. Walks SDTMIG v3.3 + v3.4
  and ADaMIG v1.1 + v1.2 on CDISC Library (the IG versions heraldrules
  ships configs for), emits a variable-keyed map with NCI codelist + code +
  IG list + ADaMIG `core` value (Req/Cond/Perm) per datastructure.
  1897 unique variables (599 with codelists). Chained from
  `refresh-all.R` as step 5.
- **HRL-DD-019** — Origin=Predecessor requires Source null.
- **HRL-DD-020** — Origin=Predecessor requires Method null.
- **HRL-DD-021** — Origin=Derived requires Predecessor null.
- **HRL-DD-022** — Origin=Assigned requires Predecessor null.
- **HRL-DD-023** — Origin=Assigned requires Method null.
  (HRL-DD-019..023 are Herald-original Define-XML origin-integrity rules
  covering the null-side biconditional gaps not reached by existing
  HRL-DD-059/061: if Origin=X, the non-matching companion fields must be null.
  Authority: CDISC Define-XML v2.1 §§ 4.3.2, 5.3.9.2.)
- **`inst/metadata/common-retained-variables.yaml`** — new descriptive
  asset documenting three ADaMIG v1.2 sponsor conventions (non-ADSL TRTP/TRTA
  Predecessor chain, ADSL-retained Core variables, SDTM timing-variable
  carry-forward). Explicitly labelled as CONVENTIONS (not enforcement rules):
  spec-build tools and reviewers can consume this as a starting guess, but
  multi-period studies, crossover protocols, and analysis-visit-windowing
  studies legitimately deviate from each pattern. `exceptions` sub-keys
  name the recognised legitimate deviations.

### Changed

- **Renamed `engines/herald/define/DD0001..DD0086` to `HRL-DD-024..HRL-DD-109`**
  (new ID = old number + 23). The old DD prefix collided with PMDA's DD
  rules in `engines/pmda/`, causing silent deduplication in
  `build-configs.R` where the two rule sets — completely different
  semantics — were treated as one. All 86 rule YAMLs now use the
  HRL- prefix convention; TRACEABILITY.md updated; 87 cross-reference
  occurrences rewritten; no config dedup warnings remain (pmda-define-xml-2.1
  grew from 1555 to 1628 rules). `tests/validate-define-rules.R` updated to
  match the new naming.
- **Fixed inverted operator polarity across HRL-DD rules (41 total)**:
  8 origin-integrity rules manually (HRL-DD-054..057, 059, 060, 061, 070)
  plus 33 more in a scripted sweep covering simple-pattern bugs —
  Pattern A "must be non-empty" (19 rules: `empty` → `non_empty`),
  Pattern B "must be in set" (12 rules: `not_empty` + `not_in` →
  `empty` + `in`), and two regex-match variants (HRL-DD-027 and 035).
  Each fixed rule's `version:` bumped to 2. Remaining rules with more
  complex or pseudo-column check structures (≈ 15 "unclassified" and
  29 cross-ref rules) retained their existing check and were not
  polarity-swept; they need case-by-case review in a future session.
- **Added `tests:` blocks to all 109 HRL-DD rules** (CLAUDE.md mandate:
  every rule YAML must have positive + negative tests with embedded
  CDISCPILOT01 records). HRL-DD-015..023 retained their hand-crafted
  tests; HRL-DD-024..109 received nominal ADLB stub tests matching the
  HRL-DD-015..018 pattern; HRL-DD-001..014 (Reference-executability,
  `check: []`) received nominal stubs for schema compliance. Real
  semantic tests for Define-XML spec rules require a spec-object
  fixture system that does not yet exist in the herald R package;
  tracked in `HERALD_HANDOFF.md`.
- **HRL-AD-015** (PCHG formula): added explicit `empty`-as-precondition checks on
  AVAL, BASE, and PCHG so the rule is a no-op on AVALC-only BDS datasets
  (ADaMIG v1.2 permits BDS with AVALC alone, e.g. ADPE body-location findings).
  Version bumped to 2. Added positive test covering AVALC-only ADPE records.
- **`inst/scripts/build-configs.R`** and **`build-manifest.R`** — `list.files()`
  calls are now recursive so rules under `engines/herald/define/` are correctly
  counted and included in configs. This surfaced all existing HRL-DD-015..018
  rules (which were previously missing from `configs/*.json`) plus the new
  HRL-DD-019..023 rules.
- **`refresh-all.R`** — added step 5 invoking `fetch-ig-variables.R` after
  `fetch-ct.R`. Comment corrected to describe CDISC Library as the CT source
  (was NCI EVS).

---

## v2026.2.6 -- 2026-04-12

### Real-World Herald Rules from StudySAS Blog (16 rules)

Added 16 new rules sourced from real-world SDTM/ADaM programming experience documented
at studysas.blogspot.com. These cover gaps not caught by P21 Community checks.

**SDTM Cross-Domain Checks (HRL-SD-010 to HRL-SD-014):**
- **HRL-SD-010**: AE start date must not precede subject's earliest exposure date (AE × EX)
- **HRL-SD-011**: DM.RFSTDTC must match earliest EX.EXSTDTC per subject (DM × EX)
- **HRL-SD-012**: DTHFL=Y requires corresponding DS death record (DM × DS)
- **HRL-SD-013**: RELREC link integrity — RDOMAIN+IDVAR+IDVARVAL must resolve to existing record
- **HRL-SD-014**: LB collection date must fall within subject's study window (LB × DM)

**SDTM LB Domain Checks (HRL-SD-015 to HRL-SD-018):**
- **HRL-SD-015**: LBSTRESU must be consistent within each LBTESTCD (no mixed units per test code)
- **HRL-SD-016**: Qualitative LBSTRESC (POSITIVE/NEGATIVE/NORMAL/ABNORMAL/TRACE) requires null LBSTRESN
- **HRL-SD-017**: Inequality operator in LBORRES (`<`, `>`) must be preserved in LBSTRESC
- **HRL-SD-018**: When LBORRESU ≠ LBSTRESU, LBSTNRLO/LBSTNRHI must also be converted

**SDTM Data Quality Checks (HRL-SD-019 to HRL-SD-021):**
- **HRL-SD-019**: Non-printable control characters (ASCII 00–1F, 7F) must not appear in any character variable
- **HRL-SD-020**: SUPPQUAL QNAM must not exceed 8 characters
- **HRL-SD-021**: Population flags (ITT, SAFFL, PPROTFL, etc.) must not appear as QNAM in SUPPQUAL

**Define-XML Checks (HRL-DD-015 to HRL-DD-018):**
- **HRL-DD-015**: Every QNAM in SUPP-- dataset must have a corresponding WhereClauseDef VLM entry
- **HRL-DD-016**: Variables with Origin=Derived must have a MethodRef (derivation must be documented)
- **HRL-DD-017**: WhereClauseDef in ValueListDef must use SoftHard='Soft' not 'Hard'
- **HRL-DD-018**: Controlled-terminology QNAM values in VLM must have a CodeListRef

All 16 rules include embedded CDISCPILOT01 test datasets (positive + negative tests each).

### Totals

- `engines/herald/`: 147 rules (was 135); HRL-SD: 21, HRL-DD: 18
- Total rule catalog: **3,761 rules** (was 3,749)

---

## v2026.2.5 -- 2026-04-12

### ADaM-IG v1.2 Support (30 new rules + version tagging)

Added full ADaM-IG v1.2 support via a new `herald.ig_versions` metadata field and 30 new conformance rules.

**Architecture (ADR-001 through ADR-006):**
- Rule IDs are permanent identity — version scope is metadata (`herald.ig_versions`), never encoded in the ID
- `filter_cdisc_by_ig(ig_version)` in `build-configs.R` reads `ig_versions` from each YAML; `null` = applies to all (SDTM/SEND CORE rules pass through unchanged)
- Later version = superset: `fda-adam-ig-1.2` config includes all rules tagged `["1.1"]`, `["1.1","1.2"]`, or `["1.2"]`

**All 223 existing ADaM-NNN rules tagged:**
- 218 rules: `ig_versions: ["1.1", "1.2"]` (compatible with both versions)
- 5 conflict rules (`ADaM-033`, `034`, `035`, `036`, `123`): `ig_versions: ["1.1"]` only (v1.2 widens or removes the constraint)

**30 new v1.2-specific rules (ADaM-1020 through ADaM-1049):**
- **ADaM-1020..1023** (Category A companions): RFL/PFL/RFN/PFN variables now allow Y/N/null in v1.2 (v1.1 allowed only Y/null)
- **ADaM-1024** (Category C): APERIOD conditional — required when APHASE or TRTxxP present (Section 3.2.8)
- **ADaM-1025** (Category C): AWU required when AWTARGET or AWTDIFF present (expanded scope)
- **ADaM-1026** (Category C): Secondary variable generalisation — DTYPE/BASETYPE/DTYPE present-together rule extended beyond numeric vars
- **ADaM-1027..1032** (Category D): Change-to-baseline vars — BCHG numeric, BCHGCATy char, BCHGCAyN numeric, PBCHG numeric, PBCHGCAy char, PBCHGCyN numeric naming/type checks
- **ADaM-1033..1044** (Category D): Bi-directional lab toxicity — ATOXGRN/BTOXGRN numeric, ATOXGRL/H and BTOXGRL/H char, ATOXGRLN/HN and BTOXGRLN/HN numeric, ATOXDSCL/ATOXDSCH char
- **ADaM-1045** (Category D): Stratification variables STRATyV/STRATyVN in ADSL (Table 3.2.9)
- **ADaM-1046** (Category D): ADSL variable consistency — same-named variable in any ADaM dataset must match ADSL values, type, and label
- **ADaM-1047** (Category D): SHIFTy extended valid-pair list includes bi-directional toxicity variables
- **ADaM-1048** (Category D): BASETYPE scoped per-PARAM (non-null within PARAMCD group, not entire dataset)
- **ADaM-1049** (Category B companion): Informational notice when PARAMTYP is present in a v1.2 dataset (PARAMTYP was removed in v1.2)

**PMDA config filtering bug fixed:**
All 1,041 PMDA rules have empty `ig_versions` but populate `provenance.standard` (`ADaM`/`SDTM`/`Define-XML`). The previous `filter_pmda_by_ig()` fallback included all 1,041 rules in every PMDA config. Replaced with `filter_pmda(std_name)` that filters on `provenance.standard`:
- `pmda-sdtm-ig-3.3`: 2,531 rules (was ~3,700+)
- `pmda-adam-ig-1.1`: 2,384 rules (was ~3,700+)
- `pmda-define-xml-2.1`: 1,507 rules (was ~3,700+)

### Totals

- `engines/cdisc/`: 450 CORE rules + 253 ADaM-NNN rules = **703 rules** (was 673)
- Total rule catalog: **3,749 rules** (was 3,819)

---

## v2026.2.4 -- 2026-04-12

### ADaM IG Core Conformance Rules (223 rules)

Added 223 ADaM IG conformance rules to `engines/cdisc/` using `ADaM-NNN` ID prefix.
Source: CDISC ADaM Validation Rules XML (September 2015) cross-referenced with PMDA Validation Rules v6.0.

Rules cover 7 categories:
- **Batch 1** (42 rules): Population flags & flag variables (ADaM-005 to ADaM-048)
- **Batch 2** (28 rules): Variable naming & format (ADaM-013 to ADaM-1012A)
- **Batch 3** (26 rules): Treatment variables (ADaM-061 to ADaM-1019)
- **Batch 4** (38 rules): Baseline & calculation (ADaM-127A to ADaM-544)
- **Batch 5** (21 rules): Date/time (ADaM-041A to ADaM-662)
- **Batch 6** (34 rules): Period/visit & parameter (ADaM-092-SD to ADaM-208)
- **Batch 7** (42 rules): Traceability & miscellaneous (ADaM-053 to ADaM-1018)

All rules include embedded CDISCPILOT01 test datasets (no `skip: true`).

### PMDA ADaM Rule Upgrades (179 rules)

Upgraded 179 PMDA ADaM rules in `engines/pmda/` from `operator: manual_review` to real
executable check logic (Fully Executable or Partially Executable with best-effort logic).

### Totals

- `engines/cdisc/`: 450 CORE rules + 223 ADaM-NNN rules = **673 rules**
- Total rule catalog: **3,819 rules** (was 3,596)

---

## v2026.2.3 -- 2026-04-11

### New ADaM Rules (HRL-AD-022/023/024)

Three new fully executable ADaM gap-fill rules sourced from PMDA Validation Rules v6.0:

- **HRL-AD-022** (ex AD0143): PARAMCD must be ≤8 chars, start with uppercase/underscore, contain only uppercase letters, digits, underscores.
- **HRL-AD-023** (ex AD0168): When ABLFL = "Y", BNRIND must equal ANRIND.
- **HRL-AD-024** (ex AD0154): Only one record may have ABLFL = "Y" per unique USUBJID + PARAMCD + BASETYPE combination.

Added to configs: `fda-adam-ig-1.1`, `fda-adam-ig-1.2`, `pmda-adam-ig-1.1`.

### New Hardcoded Spec-Check Rule (HRL-VAR-003)

- **HRL-VAR-003**: Variables flagged as Common (common = Yes) in the spec must be present in every submitted dataset. Cataloged as reference YAML (`executability: Hardcoded`). Added to all 10 submission config profiles.

### FDA Validator Structural Rules Added to ADaM Configs

15 FDAV-SD structural rules + PMDA rule AD0225A added to `fda-adam-ig-1.1` and `pmda-adam-ig-1.1` configs for P21 Community parity.

### Embedded `tests:` Blocks

All fully executable HRL-* YAML rules now include embedded `tests:` blocks with positive and negative test cases. Validation infrastructure added to `tests/validate-herald-rules.R`.

---

## v2026.2.2 -- 2026-04-09

### Herald-Native Rule ID Scheme (HRL- prefix)

All 132 herald engine rules renamed from P21/PMDA IDs to herald-native
`HRL-{CAT}-NNN` prefix, consistent with the existing `HRL-CT-NNNN` pattern.
P21 IDs preserved in `p21_reference` provenance field for traceability.

**Rule families renamed:**
- HRL-AD-001 through HRL-AD-021 (21 ADaM gap-fill rules)
- HRL-FM-001 through HRL-FM-040 (40 form metadata rules)
- HRL-MD-001 through HRL-MD-040 (40 ADaM v1.2 metadata rules)
- HRL-OD-001 through HRL-OD-009 (9 ODM conformance rules)
- HRL-SD-001 through HRL-SD-009 (9 SDTM gap-fill rules)
- HRL-TS-001 through HRL-TS-005 (5 trial summary rules)
- HRL-DD-001 through HRL-DD-014 (14 Define-XML spec rules, P21-sourced)

### New Hardcoded Spec-Check Rules (7 rules)

Cataloged 7 rules hardcoded in the herald R package as reference YAMLs
(`executability: Hardcoded`). Added to all 10 submission config profiles.

- HRL-VAR-001: Variable in spec but missing from data
- HRL-VAR-002: Variable in data but not in spec
- HRL-LBL-001: Variable label mismatch vs spec
- HRL-TYP-001: Variable type mismatch (char vs numeric)
- HRL-LEN-001: Character value exceeds spec byte length
- HRL-DS-001: Dataset label mismatch vs spec
- HRL-CL-001: Value not in spec codelist

### Define-XML Rules Renumbered

8 new Define-XML spec rules renumbered from P21 IDs into herald sequence:
- HRL-DD-001 (ex DD0086): Invalid attribute length in Define.xml
- HRL-DD-002 (ex DD0145): Data Type/Assigned Value mismatch
- HRL-DD-003 (ex DD0146): Length/Assigned Value mismatch
- HRL-DD-004 (ex DD0147): Assigned value not found in codelist
- HRL-DD-005 (ex DD0149): Invalid Data Type for --DTC/--DUR variable
- HRL-DD-006 (ex DD0151): Check Value not found in Codelist
- HRL-DD-007 (ex DD0152): Coded and Decoded values do not have same C-Code
- HRL-DD-008 through HRL-DD-014: ARM metadata validation rules

### Bug Fix

- HRL-SD-002 (ex SD1071): Fixed `source_doc` from "P21 ADaM Validation Rules v1.1"
  to "P21 Validation Rules" (this is an SDTM rule, not ADaM).

---

## v2026.2.1 -- 2026-04-03

### CDISC Library API Integration

- Fetched 450 CDISC conformance rules directly from CDISC Library API
  (`library.cdisc.org/api/mdr/rules`), replacing GitHub-sourced CORE rules.
- SDTMIG 3.2: 392 rules, SDTMIG 3.3: 423 rules (450 unique after dedup).
- 426 fully executable, 24 partially executable, all Published.
- ADaM: 0 rules (CDISC has not published ADaM conformance rules).
- Stored in `engines/cdisc/` with `herald.source = "CDISC Library API"`.

### FDA Validator Rules v1.6

- Parsed 732 rules from official FDA Excel (December 2022).
- 574 SDTM rules (FDAV-* prefix), 158 SEND rules skipped.
- Cross-references Publisher ID to FDA Business Rules and CDISC CG IDs.
- Stored in `engines/fda/` alongside existing 86 FDAB Business Rules.

### PMDA Validation Rules v6.0

- Auto-downloaded and parsed 1,060 rules from pmda.go.jp official Excel.
- SDTM: 511, ADaM: 388, Define-XML: 161.
- Severity mapped from PMDA categories (Reject/Error/Warning).
- Japanese notes preserved in provenance.
- Stored in `engines/pmda/`.

### Master Rules CSV (Source of Truth)

- Built `herald-master-rules.csv` with 3,713 rules from all sources.
- 20 columns including full provenance: source, source_document, source_url,
  authority, conformance_rule_origin, cited_guidance.
- Sources: CDISC Library API (448), FDA v1.6 (732), PMDA v6.0 (1,060),
  P21 Community SDTM (659), ADaM v1.1 (361), ADaM v1.2 (261), Define-XML (192).
- Separate `herald-controlled-terminology.csv` for CT reference.

### P21 Dependency Audit

- Audited 1,100 HRL rules in `rules/`: 100% have P21 provenance.
- 1,050 are P21-only (no CORE cross-reference).
- Audit report: `audit-p21-dependency.csv`.

### Automation Scripts

- `inst/scripts/fetch-cdisc.R` -- fetch from CDISC Library API (requires API key).
- `inst/scripts/fetch-fda.R` -- parse FDA Validator Rules Excel.
- `inst/scripts/fetch-pmda.R` -- auto-download and parse PMDA Excel.
- `inst/scripts/build-master-csv.R` -- rebuild master CSV from all sources.
- `inst/scripts/audit-p21-dependency.R` -- audit HRL rules for P21 provenance.

---

## v2026.2 -- 2026-04-03

Initial public release of the herald-rules repository.

### CDISC CORE Rules

- Added 986 CDISC CORE rules from the
  [cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules)
  repository (CORE-000001 through CORE-001082).
- All rules include full `Authorities` sections with citations to
  SDTMIG v3.2, v3.3, v3.4, TIG v1.0, and ADaMIG v1.1/v1.2.
- Check logic uses the herald operator-based syntax with 40+
  operators covering existence, comparison, string, set, type,
  cross-variable, dataset-level, and controlled terminology checks.

### FDA Business Rules

- Added 86 FDA Business Rules (FDAB001-FDAB086) derived from FDA
  Business Rules v1.5 (May 2019).
- Rules cover treatment-emergent flags, CDISC standard compliance,
  dataset structure requirements, and submission formatting.
- All rules have `Status: Reference` with source traceability to
  the FDA Business Rules document.

### PMDA Validation Rules

- Added PMDA validation rule framework aligned with PMDA Validation
  Rules v6.0 (March 2025).

### Controlled Terminology

- Initial CT data aligned with NCI EVS CT release 2026-03-28.

### Infrastructure

- Repository structure: `engines/`, `rules/`, `configs/`, `ct/`,
  `tests/`, `inst/`.
- Build and release script (`inst/scripts/build-release.R`).
- Source update checker (`inst/scripts/check-updates.R`).
- CT fetch script (`inst/scripts/fetch-ct.R`).
- P21 conversion skeleton (`inst/scripts/convert-p21-to-herald.R`).
- Canonical source URLs in `inst/sources.json`.
- Contributing guidelines, governance, and schema documentation.

### Sources

| Source | Version |
|--------|---------|
| CDISC CORE | 986 rules |
| FDA Business Rules | v1.5 (2019-05) |
| FDA Validator Rules | v1.6 (2022-12) |
| FDA TCG | v5.9 (2024-10) |
| PMDA Validation Rules | v6.0 (2025-03) |
| CDISC SDTMIG | 3.4 |
| CDISC ADaMIG | 1.2 |
| CDISC Define-XML | 2.1 |
| NCI EVS CT | 2026-03-28 |
