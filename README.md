# herald-rules

Regulatory validation rule catalog for the [herald](https://github.com/vthanik/herald) R package -- clinical dataset submission infrastructure that replaces metacore + xportr + Pinnacle 21.

All rules follow the public regulatory corpus: FDA Study Data
Technical Conformance Guide, PMDA Validation Rules v6.0, CDISC CORE
rule catalogue, CDISC IG conformance tables, and CDISC controlled
terminology releases. Each rule YAML's `provenance` block cites the
specific document and section it enforces.

## Overview

**3,878 YAML rules** (3,700 runnable, 95%) covering FDA, PMDA, and CDISC conformance requirements for SDTM, ADaM, SEND, and Define-XML submissions.

| Engine | Total | Runnable | Source |
|--------|------:|---------:|--------|
| `cdisc` | 703 | 701 | CDISC Library API (SDTM/SEND, 450 CORE rules) + ADaM IG Conformance (253 ADaM-NNN rules, v1.1 and v1.2) |
| `fda` | 660 | 574 | FDA Business Rules v1.5 (86) + Validator Rules v1.6 (574) |
| `pmda` | 1,045 | 1,039 | PMDA Validation Rules v6.0 (SDTM/ADaM/Define-XML) + 4 P21-parity gap-fills (AD0792/793/794/895) |
| `ct` | 1,210 | 1,210 | CDISC Library Controlled Terminology (6 meta-rules + 1,204 per-codelist) |
| `herald` | 260 | 176 | Herald-original: 21 executable HRL-MD spec-metadata rules + 40 deprecated HRL-FM duplicates + 90 other HRL-AD/OD/SD/TS/VAR/LBL/TYP/LEN/DS/CL + 109 HRL-DD Define-XML |

**Runnable vs catalogued.** A rule is *runnable* when its
`executability` is `Fully Executable` or `Hardcoded` — the herald engine
executes these against your data. A rule is *catalogued* (i.e.
`executability: Reference`) when it documents a regulatory expectation
herald cannot execute today — either a missing operator, a missing data
source, or a guidance-level statement. Live counts per engine are in
`manifest.json` under `stats.executable_by_engine`. The master CSV's
`runnable` column is the per-rule ground truth.

## Beat Pinnacle 21 — program roadmap

herald-rules + herald together are executing a multi-session program to
reach parity with (and ultimately exceed) Pinnacle 21 Community. Current
state and plan:

| Phase | Status | Scope |
|---|---|---|
| 1 | **done** | AD0124 executable, AD0047 clean Reference, 4 missing P21 IDs, engine handover written |
| 2a | **done** | 40 HRL-FM duplicates deprecated; 21 HRL-MD promoted Reference→Fully Executable; 19 HRL-MD annotated as operator-blocked |
| 2b-prep | **done** | Runnable allow-list expanded to include Partially Executable variants (654 rules recovered); 2 true stubs purged (ADaM-047, AD0256) |
| 2b | **done** | 86 FDA Business Rules schema-normalized; 1 remaining Not-Executable stub (ADaM-1047) purged to Reference |
| 2c | **done** | 25 un-annotated herald Reference rules (ODM/SD/DD) tagged with exact operator blockers; HANDOFF §4h (XML) + §4i (ARM) added; 84 `check: []` stubs stripped; define validator fixed to distinguish Reference from executable |
| 6 | **done** | `inst/benchmarks/p21-parity/` harness with 5 fixtures + truth table + diagnostic-mode runner -- regression floor for reviewer-cited findings |
| 3 | blocked on herald | Implement the 56 operators specified in HANDOFF §4 to unlock ~230 additional rules |
| 3 | blocked on herald | 28 new operators (required_variables, in_range, paired-suffix date/time, cross-dataset population, etc.) |
| 4 | blocked on Phase 3 | 163 additional rules unlocked by Phase 3 operators |
| 5 | blocked on Phase 4 | Re-examine 259 "architecturally blocked" + 673 "reference-by-nature" rules |
| 6 | blocked on Phase 5 | P21-parity benchmark harness (`inst/benchmarks/p21-parity/`) |
| 7 | blocked on Phase 6 | Launch prep, CRAN smoke, v0.x tag |

Engine-side work (herald R package) is tracked in
[`HANDOFF_TO_HERALD_2026-04-18.md`](HANDOFF_TO_HERALD_2026-04-18.md) — the
honesty guard in `R/rule-execute.R`, the `validate()` skip-summary, the
`required_variables` operator, and the full 28-operator specification.

## Repository Structure

```
herald-rules/
├── engines/
│   ├── cdisc/              703 YAML -- CDISC Library conformance rules (450 CORE) + ADaM IG (253 ADaM-NNN, v1.1+v1.2)
│   ├── ct/               1,210 YAML -- Per-codelist CT rules with baked-in terms
│   ├── fda/                660 YAML -- FDA Business + Validator Rules
│   ├── herald/             147 YAML -- Herald-original gap-fill + hardcoded spec checks (HRL- prefix)
│   │   └── define/         109 YAML -- Define-XML v2.1 spec validation (HRL-DD-001..109)
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
id: HRL-DD-037
version: 2
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
      operator: not_equal_to
      value: SDTMIG
    - name: standard_version
      operator: in
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

109 rules validate P21 Excel specifications against the CDISC Define-XML v2.1 standard before `write_define_xml()` generates output:

| Group | Rules | What they validate |
|-------|------:|-------------------|
| P21-Sourced (Reference) | HRL-DD-001..014 | Assigned value type/length/codelist, DTC data types, ARM metadata |
| Herald-Original Extensions | HRL-DD-015..023 | SUPPQUAL VLM completeness, method/codelist refs, origin biconditionals |
| Study Metadata | HRL-DD-024..028 | StudyName, StudyDescription, ProtocolName, DefineVersion |
| Dataset Definitions | HRL-DD-029..043 | Class, standard versions, key variables, structure, purpose |
| Variable Definitions | HRL-DD-044..063 | Data types, length, origin/source/traceability |
| Value-Level Metadata | HRL-DD-064..070 | Where clause comparators, parent length constraints |
| Codelist Definitions | HRL-DD-071..078 | NCI codes, data type, decoded values |
| Methods & Comments | HRL-DD-079..086 | Type (Computation/Imputation), descriptions |
| Cross-Reference | HRL-DD-087..096 | All ID linkages between spec sheets |
| Orphan Detection | HRL-DD-097..100 | Unreferenced methods, comments, codelists |
| P21 Alignment | HRL-DD-101..109 | ARM metadata, origin consistency, datatype match |

> **Rename note:** HRL-DD-024..109 were previously numbered DD0001..DD0086
> (new number = old + 23). Renamed to avoid ID collision with PMDA's
> DD-series rules in `engines/pmda/`; both sets now live in distinct
> namespaces.

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
