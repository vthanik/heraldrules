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

## Operator Semantics (CRITICAL — read before writing any `check:` block)

Herald's rule engine uses **passing-condition semantics**: the operator name describes what **valid data should look like**, and the function internally returns `TRUE` for **violations**. The `check:` block is NOT a violation template — it is a description of correct data, and the engine flags rows that fail to meet it.

### Core convention

```
operator name  = what valid data SHOULD do
operator body  = returns TRUE when data VIOLATES that expectation
```

Source: `R/rule-operator.R:9` — *"each operator returns TRUE where a VIOLATION is found"*

### Quick-reference: error-prone operators

| Operator | Passes when data... | Flags (violation) when data... |
|----------|--------------------|-----------------------------|
| `equal_to` | equals the value | **does not** equal the value |
| `not_equal_to` | does not equal | **does** equal |
| `in` | is in the set | **is not** in the set |
| `not_in` | is not in the set | **is** in the set |
| `empty` | is empty/null | **is populated** |
| `non_empty` | is populated | **is empty/null** |
| `matches_regex` | matches pattern | **does not** match |
| `does_not_match_regex` | does not match | **does** match |
| `less_than` | is < value | is **≥** value |
| `greater_than` | is > value | is **≤** value |
| `less_than_or_equal_to` | is ≤ value | is **>** value |
| `greater_than_or_equal_to` | is ≥ value | is **<** value |
| `not_equal_to_variable` | — | x **≠** other column (exception: this one flags the mismatch directly) |
| `equal_to_variable` | — | x **=** other column (flags the match directly) |

> **Note on cross-variable operators**: `not_equal_to_variable` and `equal_to_variable` use their literal body (`x != other` and `x == other`) — they do NOT invert. Use them directly to describe the violation state.

### `all:` vs `any:` combiner semantics

- **`all:`** — flags a row only when **every** condition's violation function returns `TRUE`
  - Use for: multi-condition violations where ALL parts must be present (pre-conditions + check)
  - Pattern: pre-conditions come first, actual check is last

- **`any:`** — flags a row when **any** condition's violation function returns `TRUE`
  - Use for: "flag if outside range A OR outside range B" (independent violation reasons)

### Conditional rule pattern (IF X THEN Y)

To express: *"When FIELD = VALUE, some other condition must hold"*

```yaml
# WRONG — equal_to fires when FIELD != VALUE (flags the non-matching rows)
- name: FIELD
  operator: equal_to
  value: "VALUE"

# CORRECT — not_equal_to fires when FIELD == VALUE (pre-condition met → engine checks further)
- name: FIELD
  operator: not_equal_to
  value: "VALUE"
```

The pre-condition must use the **opposite** of the intuitive operator so that it fires when the condition IS true, allowing `all:` to proceed to the actual check.

### "At least one of X or Y must be populated" pattern

```yaml
# WRONG — any: + non_empty fires when EITHER is empty (too aggressive)
check:
  any:
    - name: X
      operator: non_empty
    - name: Y
      operator: non_empty

# CORRECT — all: + non_empty fires only when BOTH are empty
check:
  all:
    - name: X
      operator: non_empty
    - name: Y
      operator: non_empty
```

### Verification checklist — run mentally before committing any rule

1. **Positive test**: substitute the passing record into each operator. Each operator's violation function should return `FALSE`. Combined result should yield 0 findings.
2. **Negative test**: substitute the failing record. Each relevant operator should return `TRUE`. Combined result should yield ≥ 1 finding.
3. **Conditional rules**: the pre-condition operator should return `TRUE` (fire) when the IF-condition IS met.
4. **Presence checks**: if the rule means "must be populated", use `non_empty` (violation = empty). If the rule means "must be null/empty", use `empty` (violation = populated).
5. **Range checks**: `less_than` flags rows where the value is ≥ the threshold. If you want to flag values that are too small, use `greater_than_or_equal_to`.

### Known past mistakes (2025-04)

These 12 HRL-SD rules had all operators inverted (treated `check:` as violation template instead of passing template): HRL-SD-010, 011, 012, 013, 014, 016, 017, 018, 020, 021. HRL-TS-002 and HRL-TS-004 had `any:` where `all:` was needed.

---

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
- **Do NOT edit any rule YAML's `version:` field until the herald R package reaches CRAN.** Rule content edits are fine; the `version:` number stays at 1 across the pre-CRAN lifetime so downstream pipelines that key off it don't spuriously see drift.
- **Never edit the sibling herald R package (`../herald/`) directly from this repo's Claude session.** When a rule change requires matching code in `R/val-checks.R`, `R/val-engine.R`, `R/rule-execute.R`, or any other herald file, write a handover note to `HANDOFF_TO_HERALD.md` (or a dated variant) describing the required changes, then let the user apply them in a fresh Claude session opened inside the herald repo. This keeps each repo's review, test, and commit boundaries clean. The global rule in `~/.claude/CLAUDE.md` about syncing sibling repos still applies — but the *execution* of the sync happens from the herald session, not here.
- SEND rules deferred to post-CRAN release
- ADaM: 253 ADaM IG conformance rules in engines/cdisc/ (ADaM-NNN prefix, v1.1+v1.2) + PMDA (388 rules); ADaM-1020..1049 are herald-authored v1.2-specific rules; all rules carry `herald.ig_versions` for version-filtered config assembly
- CT rules: each codelist gets its own executable YAML with terms baked in
- Every rule YAML must include a `tests:` block with at least one `type: positive` and one `type: negative` test using embedded CDISCPILOT01 records; no `skip: true` is allowed

## Validation

```bash
Rscript tests/validate-rules.R          # All engines: YAML, IDs, configs, manifest
Rscript tests/validate-herald-rules.R   # HRL-* rules: sequences, CSV coverage, operators
Rscript tests/validate-define-rules.R   # HRL-DD rules: spec sections, cross-refs, CSV
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
| `HRL-DD-NNN` | Define-XML spec | `engines/herald/define/` | 109 rules (HRL-DD-001..023 herald-original, HRL-DD-024..109 renamed from old DD0001..DD0086 to avoid collision with PMDA DD rules) |
| `HRL-VAR/LBL/TYP/LEN/DS/CL-NNN` | Hardcoded spec checks | `engines/herald/` | 12 rules (CL: 001, 002, 010, 020, 021; remainder 7) |
| `HRL-CT-NNNN` | CT per-codelist | `engines/ct/` | 1,210 rules |

P21 IDs preserved in `p21_reference` provenance field. The `DDnnnn` bare prefix is now reserved for PMDA-authored rules in `engines/pmda/` (from PMDA Validation Rules v6.0). Previously DD prefix was shared with herald/define/ rules, which caused silent config deduplication and was resolved by renaming herald/define/DD00nn → HRL-DD-NNN where NNN = nn + 23.

## Cross-Reference: Herald R Package

The herald R package (sibling repo at `../herald/` relative to this one) consumes rules from this catalog.

### Key Files in Herald R Package
- `R/val-checks.R` -- 12 hardcoded HRL-* spec checks (`HRL-VAR-001/002/003`, `HRL-LBL-001`, `HRL-TYP-001`, `HRL-LEN-001`, `HRL-DS-001`, `HRL-CL-001/002/010/020/021`)
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

- `herald-master-rules.csv` -- 2,862 rules, 20 columns, full provenance (source of truth)
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
