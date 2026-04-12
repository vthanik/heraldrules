# CLAUDE.md -- herald-rules

Regulatory validation rule catalog for the herald R package.
All rules sourced from official regulatory authorities -- zero P21 dependency.

## Architecture

```
engines/
  cdisc/   703 YAML  -- CDISC Library API (450 SDTM/SEND CORE rules) + ADaM IG Conformance (253 ADaM-NNN rules, v1.1+v1.2)
  fda/     660 YAML  -- FDA Business Rules v1.5 (86) + Validator Rules v1.6 (574)
  pmda/  1,041 YAML  -- PMDA Validation Rules v6.0 (SDTM/ADaM/Define-XML)
  ct/    1,210 YAML  -- 6 meta-rules + 1,204 per-codelist CT rules
ct/                  -- Full SDTM + ADaM controlled terminology JSON
configs/             -- 10 submission profile configs (FDA/PMDA x IG versions)
```

## YAML Schemas

Two schemas coexist:
- **PascalCase** (CDISC CORE format): `engines/cdisc/`, `engines/fda/`
  - Keys: `Core.Id`, `Description`, `Check`, `Outcome`, `Authorities`
- **lowercase** (herald format): `engines/pmda/`, `engines/ct/`
  - Keys: `id`, `description`, `check`, `outcome`, `provenance`

## Quarterly Refresh

```bash
Rscript inst/scripts/refresh-all.R          # Full refresh (fetch + rebuild)
Rscript inst/scripts/refresh-all.R --skip-fetch  # Rebuild only
Rscript inst/scripts/refresh-all.R --dry-run     # Preview
```

Individual scripts:
- `fetch-cdisc.R` -- CDISC Library API (requires API key)
- `fetch-fda.R` -- FDA Validator Rules Excel (manual download)
- `fetch-pmda.R` -- PMDA (auto-downloads from pmda.go.jp)
- `build-configs.R` -- Regenerate submission configs
- `build-master-csv.R` -- Rebuild master CSV
- `build-manifest.R` -- Regenerate manifest.json

## API Key

CDISC Library API key stored in `.local/.env`:
```
CDISC_API_KEY=<key>
```
Never commit `.local/` -- it's gitignored.

## Adding / Modifying / Deleting Rules — Affected Files Checklist

Every rule change touches multiple files. Use this checklist to ensure nothing is missed.
Run the rebuild scripts (see below) rather than editing configs/manifest by hand.

### When ADDING a new rule

| # | File / Action | How |
|---|---------------|-----|
| 1 | **`engines/<engine>/<rule_id>.yaml`** | Create rule YAML (positive + negative tests required) |
| 2 | **`herald-master-rules.csv`** | Append row with all 20 columns |
| 3 | **`configs/*.json`** | Run `Rscript inst/scripts/build-configs.R` — auto-adds to relevant configs |
| 4 | **`manifest.json`** | Run `Rscript inst/scripts/build-manifest.R` — auto-updates engine counts |
| 5 | **`CHANGELOG.md`** | Add entry under current version heading |
| 6 | **`README.md`** | Update engine rule count in the table (e.g. `herald \| 147`) |
| 7 | **`CLAUDE.md`** | Update rule count in Architecture block and Herald Rule ID Convention table |

### When MODIFYING an existing rule

| # | File / Action | How |
|---|---------------|-----|
| 1 | **`engines/<engine>/<rule_id>.yaml`** | Edit rule; increment `version` field |
| 2 | **`herald-master-rules.csv`** | Update the matching row |
| 3 | **`configs/*.json`** | Re-run `build-configs.R` only if scope/domains changed |
| 4 | **`manifest.json`** | Re-run `build-manifest.R` only if executability/status changed |
| 5 | **`CHANGELOG.md`** | Document what changed and why |

### When DELETING a rule

| # | File / Action | How |
|---|---------------|-----|
| 1 | **`engines/<engine>/<rule_id>.yaml`** | Set `status: Deprecated` — do NOT delete the file |
| 2 | **YAML `deprecated:` block** | Add `date`, `reason`, `replaced_by` fields |
| 3 | **`herald-master-rules.csv`** | Set status column to `Deprecated` |
| 4 | **`configs/*.json`** | Keep rule ID in configs (audit trail) — do not remove |
| 5 | **`manifest.json`** | Re-run `build-manifest.R` |
| 6 | **`CHANGELOG.md`** | Document deprecation |

### Rebuild commands (always run in order)

```bash
Rscript inst/scripts/build-configs.R    # Regenerates all configs/*.json
Rscript inst/scripts/build-manifest.R  # Regenerates manifest.json
```

### Quick verification after any rule change

```bash
# 1. No duplicate rule IDs in any config
python3 -c "
import json, glob, sys
for f in sorted(glob.glob('configs/*.json')):
    d = json.load(open(f)); ids = d['rule_ids']
    if len(ids) != len(set(ids)): print('FAIL', f); sys.exit(1)
    print('OK', f, len(ids))
"

# 2. All rule YAMLs parse cleanly
Rscript tests/validate-rules.R
```

## Rules

- Never re-introduce P21 dependency (engines/core/ was deleted, rules/ was deleted)
- Never bump version without explicit user approval
- SEND rules deferred to post-CRAN release
- ADaM: 253 ADaM IG conformance rules in engines/cdisc/ (ADaM-NNN prefix, v1.1+v1.2) + PMDA (388 rules); ADaM-1020..1049 are herald-authored v1.2-specific rules; all rules carry `herald.ig_versions` for version-filtered config assembly
- CT rules: each codelist gets its own executable YAML with terms baked in
- Every rule YAML must include a `tests:` block with at least one `type: positive` and one `type: negative` test using embedded CDISCPILOT01 records; no `skip: true` is allowed

## Validation

```bash
Rscript tests/validate-rules.R          # All engines: YAML, IDs, configs, manifest
Rscript tests/validate-herald-rules.R   # HRL-* rules: sequences, CSV coverage, operators
Rscript tests/validate-define-rules.R   # DD rules: spec sections, cross-refs, CSV
```

## Herald Rule ID Convention

ALL herald-authored rules use `HRL-{CAT}-NNN` prefix:

| Prefix | Category | Directory | Notes |
|--------|----------|-----------|-------|
| `HRL-AD-NNN` | ADaM gap-fill | `engines/herald/` | 24 rules |
| `HRL-FM-NNN` | Form metadata | `engines/herald/` | 40 rules |
| `HRL-MD-NNN` | Metadata (ADaM v1.2) | `engines/herald/` | 40 rules |
| `HRL-OD-NNN` | ODM conformance | `engines/herald/` | 9 rules |
| `HRL-SD-NNN` | SDTM gap-fill | `engines/herald/` | 21 rules |
| `HRL-TS-NNN` | Trial summary | `engines/herald/` | 5 rules |
| `HRL-DD-NNN` | Define-XML spec | `engines/herald/define/` | 18 rules |
| `HRL-VAR/LBL/TYP/LEN/DS/CL-NNN` | Hardcoded spec checks | `engines/herald/` | 8 rules |
| `HRL-CT-NNNN` | CT per-codelist | `engines/ct/` | 1,210 rules |

P21 IDs preserved in `p21_reference` provenance field. `DD0001-DD0085` keep bare DD prefix (herald-native spec rules).

## Cross-Reference: Herald R Package

The herald R package (`/home/vignesh/projects/herald/`) consumes rules from this catalog.

### Key Files in Herald R Package
- `R/val-checks.R` -- 8 hardcoded HRL-* spec checks (`HRL-VAR-001/002/003`, `HRL-LBL-001`, `HRL-TYP-001`, `HRL-LEN-001`, `HRL-DS-001`, `HRL-CL-001`)
- `R/val-engine.R` -- `validate()` orchestrator
- `R/rule-execute.R` -- YAML rule execution, `grepl("^HRL-", rule_id)` routing
- `R/rule-operator.R` -- Operator registry (96 core + 60 herald operators)
- `R/rule-fetch.R` -- Rule resolution from herald-rules cache

### Herald ↔ Herald-Rules Sync

ALWAYS keep these two repos in sync:
- Any hardcoded rule in `R/val-checks.R` must have a matching YAML in
  `engines/herald/` with `executability: Hardcoded`
- All rule IDs use `HRL-{CAT}-NNN` prefix (no HERALD- prefix, no bare P21 IDs)
- When adding/renaming hardcoded rules, update BOTH repos in the same session
- Run `Rscript tests/validate-rules.R` to verify sync

Always sync `README.md` after any rule additions, ID changes, or count updates.

## Key Files

- `herald-master-rules.csv` -- 2,402 rules, 20 columns, full provenance (source of truth)
- `herald-controlled-terminology.csv` -- 44,970 CT terms with extensibility
- `manifest.json` -- engine rule counts and config summaries
- `CHANGELOG.md` -- release history

## Sources

| Source | URL | Format |
|--------|-----|--------|
| CDISC Library API | library.cdisc.org/api/mdr/rules | JSON (API key required) |
| FDA Validator Rules v1.6 | fda.gov (manual download) | Excel |
| FDA Business Rules v1.5 | fda.gov/media/116935/download | Excel |
| PMDA Validation Rules v6.0 | pmda.go.jp/files/000274354.zip | ZIP/Excel |
| NCI EVS SDTM CT | evs.nci.nih.gov/ftp1/CDISC/SDTM/ | Tab-delimited |
| CDISC Library CT | library.cdisc.org/api/mdr/ct/packages | JSON |
