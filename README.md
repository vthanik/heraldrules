# herald-rules

Regulatory validation rule catalog for the [herald](https://github.com/vthanik/herald) R package -- clinical dataset submission infrastructure that replaces metacore + xportr + Pinnacle 21.

## Overview

**3,819 YAML rules** covering FDA, PMDA, and CDISC conformance requirements for SDTM, ADaM, SEND, and Define-XML submissions.

| Engine | Rules | Source |
|--------|------:|--------|
| `cdisc` | 673 | CDISC Library API (SDTM/SEND, 450 CORE rules) + ADaM IG Conformance (223 ADaM-NNN rules) |
| `fda` | 660 | FDA Business Rules v1.5 (86) + Validator Rules v1.6 (574) |
| `pmda` | 1,041 | PMDA Validation Rules v6.0 (SDTM/ADaM/Define-XML) |
| `ct` | 1,210 | NCI EVS Controlled Terminology (6 meta-rules + 1,204 per-codelist) |
| `herald` | 235 | Herald-original: 127 gap-fill (HRL-AD/FM/MD/OD/SD/TS) + 100 Define-XML spec + 8 hardcoded spec checks |

## Repository Structure

```
herald-rules/
├── engines/
│   ├── cdisc/              673 YAML -- CDISC Library conformance rules (450 CORE) + ADaM IG (223 ADaM-NNN)
│   ├── ct/               1,210 YAML -- Per-codelist CT rules with baked-in terms
│   ├── fda/                660 YAML -- FDA Business + Validator Rules
│   ├── herald/             135 YAML -- Herald-original gap-fill + hardcoded spec checks (HRL- prefix)
│   │   └── define/         100 YAML -- Define-XML v2.1 spec validation (DD0001--DD0086, HRL-DD-001--014)
│   └── pmda/             1,041 YAML -- PMDA Validation Rules v6.0
├── configs/                        -- 10 submission profile configs
│   ├── fda-sdtm-ig-3.2.json
│   ├── fda-sdtm-ig-3.3.json
│   ├── fda-adam-ig-1.1.json
│   ├── fda-adam-ig-1.2.json
│   ├── fda-define-xml-2.1.json
│   ├── pmda-sdtm-ig-3.2.json
│   ├── pmda-sdtm-ig-3.3.json
│   ├── pmda-adam-ig-1.1.json
│   ├── pmda-define-xml-2.1.json
│   └── all.json
├── ct/                             -- Full SDTM + ADaM controlled terminology JSON
├── inst/
│   ├── define-xml/                 -- Define-XML v2.1 assets
│   │   ├── stylesheets/           -- define2-1.xsl (renders in browsers)
│   │   └── schema/                -- XSD schemas (ODM 1.3.2, Define 2.1, ARM 1.0)
│   └── scripts/                   -- Quarterly refresh automation
├── herald-master-rules.csv         -- All rules in one CSV (source of truth)
├── herald-controlled-terminology.csv -- 44,970 CT terms with extensibility
├── manifest.json                   -- Engine counts and config summaries
├── tests/                          -- Rule validation test suite
└── RULE_SCHEMA.md                  -- Complete YAML schema documentation
```

## Rule Formats

Two YAML schemas coexist:

**PascalCase** (CDISC CORE format) -- `engines/cdisc/`, `engines/fda/`:

```yaml
Core:
  Id: CORE-000005
  Status: Published
  Version: '1'
Description: When EXTRT is PLACEBO, EXDOSE must equal 0
Check:
  all:
    - name: EXTRT
      operator: equal_to
      value: PLACEBO
    - name: EXDOSE
      operator: not_equal_to
      value: 0
Outcome:
  Message: EXTRT is PLACEBO, but EXDOSE is not equal to 0.
Rule Type: Record Data
Sensitivity: Record
Authorities:
  - Organization: CDISC
```

**lowercase** (herald format) -- `engines/pmda/`, `engines/ct/`, `engines/herald/`:

```yaml
id: DD0014
version: 1
status: Published
standard: Define-XML
category: Standards Reference
sensitivity: Dataset
executability: Fully Executable
description: >
  SDTMIG version must be one of the allowable versions: 3.1.2, 3.2, 3.3, 3.4.
check:
  all:
    - name: standard_name
      operator: equal_to
      value: SDTMIG
    - name: standard_version
      operator: not_in
      value: ["3.1.2", "3.2", "3.3", "3.4"]
outcome:
  message: "SDTMIG version is not allowable."
  severity: Error
provenance:
  source_doc: CDISC Define-XML v2.1 Specification
  authority: CDISC
  section: "4.1.1"
```

See [RULE_SCHEMA.md](RULE_SCHEMA.md) for the complete schema with all operators.

## Define-XML v2.1 Spec Validation

100 rules validate P21 Excel specifications against the CDISC Define-XML v2.1 standard before `write_define_xml()` generates output:

| Group | Rules | What they validate |
|-------|------:|-------------------|
| Study Metadata | DD0001--DD0005 | StudyName, StudyDescription, ProtocolName, DefineVersion |
| Dataset Definitions | DD0006--DD0020 | Class, standard versions, key variables, structure, purpose |
| Variable Definitions | DD0021--DD0040 | Data types, length, origin/source/traceability |
| Value-Level Metadata | DD0041--DD0047 | Where clause comparators, parent length constraints |
| Codelist Definitions | DD0048--DD0055 | NCI codes, data type, decoded values |
| Methods & Comments | DD0056--DD0063 | Type (Computation/Imputation), descriptions |
| Cross-Reference | DD0064--DD0073 | All ID linkages between spec sheets |
| Orphan Detection | DD0074--DD0077 | Unreferenced methods, comments, codelists |
| P21 Alignment | DD0078--DD0086 | ARM metadata, origin consistency, datatype match |
| P21-Sourced (HRL-DD) | HRL-DD-001--014 | Assigned value type/length/codelist, DTC data types, ARM metadata |

Traceability to specific spec sections is documented in [engines/herald/define/TRACEABILITY.md](engines/herald/define/TRACEABILITY.md).

## Submission Configs

Pre-built profiles select the right rules for each submission type:

```r
# In the herald R package:
validate(data, spec, config = "fda-sdtm-ig-3.3")
validate(data, spec, config = "pmda-adam-ig-1.1")
validate(data, spec, config = "fda-define-xml-2.1")
```

| Config | Authority | Standard | Rules |
|--------|-----------|----------|------:|
| `fda-sdtm-ig-3.2` | FDA | SDTM-IG 3.2 | 2,276 |
| `fda-sdtm-ig-3.3` | FDA | SDTM-IG 3.3 | 2,276 |
| `fda-adam-ig-1.1` | FDA | ADaM-IG 1.1 | 475 |
| `fda-adam-ig-1.2` | FDA | ADaM-IG 1.2 | 497 |
| `fda-define-xml-2.1` | FDA | Define-XML 2.1 | 2,020 |
| `pmda-sdtm-ig-3.2` | PMDA | SDTM-IG 3.2 | 2,743 |
| `pmda-sdtm-ig-3.3` | PMDA | SDTM-IG 3.3 | 2,743 |
| `pmda-adam-ig-1.1` | PMDA | ADaM-IG 1.1 | 524 |
| `pmda-define-xml-2.1` | PMDA | Define-XML 2.1 | 2,321 |
| `all` | Combined | All | 3,500 |

## Quarterly Refresh

```bash
Rscript inst/scripts/refresh-all.R          # Full refresh (fetch + rebuild)
Rscript inst/scripts/refresh-all.R --skip-fetch  # Rebuild only
Rscript inst/scripts/refresh-all.R --dry-run     # Preview
```

Individual scripts:
- `fetch-cdisc.R` -- CDISC Library API (requires API key)
- `fetch-fda.R` -- FDA Validator Rules Excel
- `fetch-pmda.R` -- PMDA (auto-downloads from pmda.go.jp)
- `build-configs.R` -- Regenerate submission configs
- `build-master-csv.R` -- Rebuild master CSV
- `build-manifest.R` -- Regenerate manifest.json

## Validation

```bash
Rscript tests/validate-rules.R          # Structural: YAML parsing, IDs, configs, manifest
Rscript tests/validate-herald-rules.R   # HRL-* rules: sequences, CSV coverage, operators
Rscript tests/validate-define-rules.R   # Content: DD rule fields, operators, provenance, values
```

## Sources

| Source | URL | Format |
|--------|-----|--------|
| CDISC Library API | library.cdisc.org/api/mdr/rules | JSON (API key required) |
| FDA Validator Rules v1.6 | fda.gov (manual download) | Excel |
| FDA Business Rules v1.5 | fda.gov/media/116935/download | Excel |
| PMDA Validation Rules v6.0 | pmda.go.jp/files/000274354.zip | ZIP/Excel |
| NCI EVS SDTM CT | evs.nci.nih.gov/ftp1/CDISC/SDTM/ | Tab-delimited |
| CDISC Library CT | library.cdisc.org/api/mdr/ct/packages | JSON |
| Define-XML v2.1 Spec | cdisc.org/define-xml | PDF/XML Schema |

## License

[MIT](LICENSE)

Rule content is derived from publicly available regulatory standards. The Define-XML v2.1 stylesheet (`define2-1.xsl`) is MIT licensed by Lex Jansen (2013--2019).
