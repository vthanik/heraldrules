# Changelog

All notable changes to herald-rules are documented in this file.

Versions follow the format `v{YYYY}.{Q}` aligned with NCI EVS
Controlled Terminology quarterly releases. See [GOVERNANCE.md](GOVERNANCE.md)
for release cadence details.

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
