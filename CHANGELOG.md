# Changelog

All notable changes to herald-rules are documented in this file.

Versions follow the format `v{YYYY}.{Q}` aligned with NCI EVS
Controlled Terminology quarterly releases. See [GOVERNANCE.md](GOVERNANCE.md)
for release cadence details.

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
