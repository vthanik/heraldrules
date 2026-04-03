# Changelog

All notable changes to herald-rules are documented in this file.

Versions follow the format `v{YYYY}.{Q}` aligned with NCI EVS
Controlled Terminology quarterly releases. See [GOVERNANCE.md](GOVERNANCE.md)
for release cadence details.

---

## v2026.2 — 2026-04-03

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
