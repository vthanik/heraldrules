# CLAUDE.md -- herald-rules

Regulatory validation rule catalog for the herald R package.
All rules sourced from official regulatory authorities -- zero P21 dependency.

## Architecture

```
engines/
  cdisc/   673 YAML  -- CDISC Library API (450 SDTM/SEND CORE rules) + ADaM IG Conformance (223 ADaM-NNN rules)
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

## Adding Rules or Engines

When adding a new rule or defining a new engine, ALL of the following must be updated:

1. **YAML rule file** -- Create in `engines/<engine>/<rule_id>.yaml`
2. **herald-master-rules.csv** -- Append row with all 20 columns
3. **Config JSON(s)** -- Add rule ID to relevant `configs/*.json` files
4. **manifest.json** -- Update engine rule counts and config rule counts
5. **CHANGELOG.md** -- Document the addition

When modifying a rule:
- Increment the `version` field in the YAML
- Update the master CSV row
- Update CHANGELOG.md

When deprecating a rule:
- Set `status: Deprecated` in YAML
- Add `deprecated` section with date, reason, replaced_by
- Update master CSV status column
- Do NOT remove from config JSON (keeps audit trail)
- Update CHANGELOG.md

## Rules

- Never re-introduce P21 dependency (engines/core/ was deleted, rules/ was deleted)
- Never bump version without explicit user approval
- SEND rules deferred to post-CRAN release
- ADaM: 223 ADaM IG conformance rules in engines/cdisc/ (ADaM-NNN prefix) + PMDA (388 rules); ADaM-NNN rules from CDISC ADaM Validation Rules XML (September 2015)
- CT rules: each codelist gets its own executable YAML with terms baked in

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
| `HRL-SD-NNN` | SDTM gap-fill | `engines/herald/` | 9 rules |
| `HRL-TS-NNN` | Trial summary | `engines/herald/` | 5 rules |
| `HRL-DD-NNN` | Define-XML spec | `engines/herald/define/` | 14 rules |
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
