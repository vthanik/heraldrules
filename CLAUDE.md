# CLAUDE.md — herald-rules

Regulatory validation rule catalog for the herald R package.
All rules sourced from official regulatory authorities — zero P21 dependency.

## Architecture

```
engines/
  cdisc/   450 YAML  — CDISC Library API (SDTMIG 3.2, 3.3 conformance rules)
  fda/     660 YAML  — FDA Business Rules v1.5 (86) + Validator Rules v1.6 (574)
  pmda/  1,041 YAML  — PMDA Validation Rules v6.0 (SDTM/ADaM/Define-XML)
  ct/    1,210 YAML  — 6 meta-rules + 1,204 per-codelist CT rules
ct/                  — Full SDTM + ADaM controlled terminology JSON
configs/             — 10 submission profile configs (FDA/PMDA x IG versions)
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
- `fetch-cdisc.R` — CDISC Library API (requires API key)
- `fetch-fda.R` — FDA Validator Rules Excel (manual download)
- `fetch-pmda.R` — PMDA (auto-downloads from pmda.go.jp)
- `build-configs.R` — Regenerate submission configs
- `build-master-csv.R` — Rebuild master CSV
- `build-manifest.R` — Regenerate manifest.json

## API Key

CDISC Library API key stored in `.local/.env`:
```
CDISC_API_KEY=<key>
```
Never commit `.local/` — it's gitignored.

## Rules

- Never re-introduce P21 dependency (engines/core/ was deleted, rules/ was deleted)
- Never bump version without explicit user approval
- SEND rules deferred to post-CRAN release
- ADaM: CDISC has 0 published conformance rules; coverage from PMDA (388 rules)
- CT rules: each codelist gets its own executable YAML with terms baked in

## Validation

```bash
Rscript tests/validate-rules.R
```

Checks: YAML parsing, required fields, no duplicate IDs, config references valid, manifest counts match.

## Key Files

- `herald-master-rules.csv` — 2,240 rules, 20 columns, full provenance (source of truth)
- `herald-controlled-terminology.csv` — 44,970 CT terms with extensibility
- `manifest.json` — engine rule counts and config summaries
- `CHANGELOG.md` — release history

## Sources

| Source | URL | Format |
|--------|-----|--------|
| CDISC Library API | library.cdisc.org/api/mdr/rules | JSON (API key required) |
| FDA Validator Rules v1.6 | fda.gov (manual download) | Excel |
| FDA Business Rules v1.5 | fda.gov/media/116935/download | Excel |
| PMDA Validation Rules v6.0 | pmda.go.jp/files/000274354.zip | ZIP/Excel |
| NCI EVS SDTM CT | evs.nci.nih.gov/ftp1/CDISC/SDTM/ | Tab-delimited |
| CDISC Library CT | library.cdisc.org/api/mdr/ct/packages | JSON |
