# P21-Parity Benchmark

Regression harness proving that herald-rules + herald together reproduce
the findings Pinnacle 21 Community would report on curated data.

## Why this exists

Herald's product goal is to be the open-source R-native replacement for
Pinnacle 21 Community. "Beat P21" means three things, in order:

1. **No silent false negatives.** Every rule that should fire, fires.
2. **Findings match reviewer expectations.** Not just our tests -- the
   actual findings a regulatory reviewer would cite.
3. **Coverage matches or exceeds P21.** Where P21 catches it, we catch it.

This benchmark codifies (1) and (2) as a regression floor. Each fixture is
a small CSV engineered to trigger a specific rule a specific number of
times. `expected-findings.csv` is the truth table. `run-benchmark.R`
compares herald's actual findings to expectations and exits non-zero on
any mismatch.

## Layout

```
inst/benchmarks/p21-parity/
  README.md                  -- this file
  run-benchmark.R            -- harness
  expected-findings.csv      -- truth table (fixture, rule_id, expected_count, status)
  fixtures/
    advs-parcat1-inconsistent.csv   -- AD0124 x1
    advs-parcat1-consistent.csv     -- AD0124 x0 (control)
    adae-missing-aesev.csv          -- AD0047 x1 (blocked on required_variables op)
    adae-complete.csv               -- AD0047 x0 (control)
    lb-lbstresu-inconsistent.csv    -- HRL-SD-015 x2
```

## Running

```bash
# From repo root
Rscript inst/benchmarks/p21-parity/run-benchmark.R
```

If the `herald` R package is not installed, the harness runs in
diagnostic mode -- it prints each expectation without executing
anything. Useful for sanity-checking the expected table.

If `herald` is installed, the harness:

1. Loads each fixture CSV as a named list
   (e.g. `list(ADVS = read.csv("advs-parcat1-inconsistent.csv"))`)
2. Calls `herald::validate(datasets, rules = <rule_id>)` once per
   expectation row
3. Counts findings matching the `rule_id`
4. Compares to `expected_count` and prints PASS/FAIL per row
5. Exits non-zero if any mismatch

`status == "blocked"` rows are skipped with a visible SKIP line citing
the herald operator they wait on. Every run thus shows the gap -- no
silent coverage loss.

## Adding a fixture

1. Drop a CSV under `fixtures/`. Use CDISCPILOT01 STUDYID and realistic
   USUBJID values. Keep files small (<5 KB) so commits stay readable.
2. Append rows to `expected-findings.csv`:
   - `fixture` -- basename of the CSV (no extension)
   - `domain` -- SDTM/ADaM dataset name (ADVS, ADAE, LB, etc.)
   - `rule_id` -- the rule being exercised
   - `expected_count` -- how many findings herald should emit
   - `status` -- `runnable_today` (engine can execute today) or `blocked`
   - `blocked_on` -- herald operator name (for `blocked` rows only;
     matches the subsection in `../../HANDOFF_TO_HERALD_2026-04-18.md`)
   - `notes` -- human-readable description of the trigger / control
3. Re-run `run-benchmark.R` to confirm the expectation parses and (if
   `runnable_today`) fires as expected.

## Contract with herald

- `herald::validate(datasets, rules = <rule_id>)` must accept a named
  list of data frames and a rule-id vector.
- Its return value is either `$findings` (a data frame) or the findings
  data frame directly. Columns must include at least `rule_id` and
  `dataset`.
- Rules whose `executability` is not in the runnable allow-list must
  short-circuit (per HANDOFF section 1). The benchmark distinguishes
  "skipped because blocked" from "executed and found 0" so we can tell
  apart coverage gaps from genuinely-clean fixtures.

## When this benchmark lights up fully

`adae-missing-aesev` is the first fixture we expect to flip from blocked
to PASS. It blocks on the `required_variables` operator (HANDOFF §3).
Once that operator lands in `../herald/R/rule-operator.R`, re-run and
the AD0047 expectation should go from SKIP to PASS with
`expected_count = 1`.

After HANDOFF §4 operators (56 total) ship, the fixture set will grow
to cover ADVS/ADLB/ADEG PARCAT1 nests, ADAE required-variable presence
per domain, ODM namespace validation, ARM metadata uniqueness, spec
metadata codelist cross-references, and more. Each added fixture is a
trust deposit: the next time herald changes, the harness catches
regressions before they reach users.
