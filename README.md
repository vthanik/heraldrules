# herald-rules

Validation rules for [herald](https://github.com/vthanik/herald) -- clinical dataset submission infrastructure for R.

## Structure

```
engines/
├── cdisc/          # CDISC Library API rules (SDTM, ADaM, SEND)
├── ct/             # NCI EVS Controlled Terminology
├── fda/            # FDA Business Rules v1.5
│   ├── .raw/       # Original Excel download
│   └── *.yaml      # Parsed YAML rules
└── pmda/           # PMDA Validation Rules (manual download)
```

## Rule Format

Each rule is a YAML file:

```yaml
Core:
  Id: FDAB001
  Status: Reference    # Reference = metadata only, Published = executable
Description: ...
Check: []              # Empty for Reference rules; executable logic added later
Outcome:
  Message: ...
Rule Type: Record Data
Sensitivity: Record
Authorities:
- Organization: FDA
Source: FDA Business Rules v1.5
```

## Updating Rules

```bash
# From the herald repo:
Rscript inst/scripts/fetch-rules.R --output-dir ../herald-rules/engines

# With CDISC Library API:
export CDISC_LIBRARY_API_KEY=your-key
Rscript inst/scripts/fetch-rules.R --output-dir ../herald-rules/engines
```

## Sources

| Source | URL | Auth |
|--------|-----|------|
| CDISC Library API | https://library.cdisc.org/api | Free API key |
| FDA Business Rules v1.5 | https://www.fda.gov/media/116935/download | None |
| NCI EVS CT | https://evs.nci.nih.gov/ftp1/CDISC/ | None |
| PMDA Validation | https://www.pmda.go.jp/english/review-services/reviews/0002.html | Manual |

## License

Rule content is sourced from public regulatory agencies. See individual source licenses.
