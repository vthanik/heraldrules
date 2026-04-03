# Contributing to herald-rules

Thank you for your interest in contributing to herald-rules. This repository
contains the validation rule definitions used by the
[herald](https://github.com/vthanik/herald) R package for clinical dataset
submission conformance. Because these rules directly affect regulatory
submissions to the FDA, PMDA, and EMA, contributions must meet a high standard
of accuracy, traceability, and review rigor.

## Table of Contents

- [Getting Started](#getting-started)
- [Repository Structure](#repository-structure)
- [Adding a New Rule](#adding-a-new-rule)
- [Modifying an Existing Rule](#modifying-an-existing-rule)
- [Deprecating a Rule](#deprecating-a-rule)
- [Writing Test Cases](#writing-test-cases)
- [Controlled Terminology Updates](#controlled-terminology-updates)
- [Configuration Changes](#configuration-changes)
- [Pull Request Process](#pull-request-process)
- [PR Review Checklist](#pr-review-checklist)
- [Commit Conventions](#commit-conventions)
- [Reporting Issues](#reporting-issues)

---

## Getting Started

1. **Fork and clone** the repository:

   ```bash
   git clone https://github.com/<your-username>/herald-rules.git
   cd herald-rules
   ```

2. **Create a feature branch** from `main`:

   ```bash
   git checkout -b feature/add-fdab087-rule
   ```

3. **Read the schema documentation** in [RULE_SCHEMA.md](RULE_SCHEMA.md)
   before writing any YAML.

4. **Validate locally** before submitting:

   ```bash
   Rscript inst/scripts/build-release.R --validate-only
   ```

---

## Repository Structure

```
herald-rules/
├── engines/
│   ├── core/           # CDISC CORE rules (CORE-000001.yaml ...)
│   ├── fda/            # FDA Business Rules (FDAB001.yaml ...)
│   ├── pmda/           # PMDA Validation Rules
│   └── ct/             # Controlled Terminology rules
├── rules/
│   ├── xpt/            # XPT transport-level rules
│   ├── sdtm/           # SDTM domain-level rules
│   ├── adam/            # ADaM domain-level rules
│   ├── define/         # Define-XML rules
│   ├── meta/           # Metadata-level rules
│   └── ct/             # Controlled Terminology rules
├── configs/            # Agency-specific rule configurations
├── ct/                 # Controlled Terminology data files
├── tests/              # Test case files
├── inst/
│   ├── sources.json    # Canonical source URLs and versions
│   └── scripts/        # Build, check, and fetch scripts
├── RULE_SCHEMA.md      # Full YAML schema documentation
├── GOVERNANCE.md       # Release cadence and decision-making
├── CHANGELOG.md        # Release history
└── CONTRIBUTING.md     # This file
```

---

## Adding a New Rule

### Step 1: Determine the Rule ID

Rule IDs follow a strict naming convention based on the source authority:

| Authority | Pattern | Example |
|-----------|---------|---------|
| CDISC CORE | `CORE-NNNNNN` | `CORE-000005` |
| FDA Business Rules | `FDABXXX` | `FDAB001` |
| PMDA Validation | `PMDAXXX` | `PMDA001` |
| herald custom | `HRLD-XXXX` | `HRLD-0001` |

- For CDISC CORE rules, use the official CORE ID from the
  [cdisc-open-rules](https://github.com/cdisc-org/cdisc-open-rules) repository.
- For FDA rules, use the next sequential `FDAB` number.
- For custom herald rules (not from any authority), use the `HRLD-` prefix.

### Step 2: Create the YAML file

Place the file in the appropriate `engines/` subdirectory:

```yaml
# Variable: EXDOSE
# Condition: EXTRT = 'PLACEBO'
# Rule: EXDOSE = 0
Core:
  Id: CORE-000005
  Status: Published
  Version: '1'
Description: When EXTRT is PLACEBO, EXDOSE must equal 0
Executability: Fully Executable
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
  Output Variables:
    - EXTRT
    - EXDOSE
Rule Type: Record Data
Scope:
  Classes:
    Include:
      - INTERVENTIONS
  Domains:
    Include:
      - EX
Sensitivity: Record
Authorities:
  - Organization: CDISC
    Standards:
      - Name: SDTMIG
        Version: '3.4'
        References:
          - Origin: SDTM and SDTMIG Conformance Rules
            Rule Identifier:
              Id: CG0102
              Version: '1'
            Version: '2.0'
            Citations:
              - Cited Guidance: >
                  Doses of placebo should be represented by EXTRT = "PLACEBO"
                  and EXDOSE = "0".
                Document: SDTMIG v3.4
                Section: 6.1.3.1
```

See [RULE_SCHEMA.md](RULE_SCHEMA.md) for complete field documentation.

### Step 3: Add test cases

Create a corresponding test case in `tests/` (see
[Writing Test Cases](#writing-test-cases)).

### Step 4: Validate

```bash
Rscript inst/scripts/build-release.R --validate-only
```

This checks:

- YAML parses without errors
- All required fields are present
- Rule ID matches filename
- Check operators are valid
- No duplicate rule IDs across engines

---

## Modifying an Existing Rule

When modifying an existing rule:

1. **Increment the Version** in the `Core` section:

   ```yaml
   Core:
     Id: CORE-000005
     Status: Published
     Version: '2'        # Was '1'
   ```

2. **Document the reason** in your PR description. Link to the upstream
   source change (CDISC release notes, FDA guidance update, etc.).

3. **Update the Authorities section** if the citation has changed.

4. **Never change a rule ID.** If a rule must be replaced, deprecate the
   old rule and create a new one.

5. **Update test cases** to reflect the modified behavior.

### Changing a rule from Reference to Published

Some rules start as `Status: Reference` (metadata only, no executable
logic). To make them executable:

1. Set `Status: Published`.
2. Add the `Check` section with valid operators.
3. Set `Executability: Fully Executable` (or `Partially Executable`).
4. Add test cases that exercise the check logic.

---

## Deprecating a Rule

Rules should never be deleted. Instead, deprecate them:

1. Set `Status: Deprecated` in the `Core` section.
2. Add a `Deprecated` section:

   ```yaml
   Core:
     Id: FDAB042
     Status: Deprecated
     Version: '2'
   Deprecated:
     Date: 2026-04-01
     Reason: Superseded by CORE-000350
     Replaced_By: CORE-000350
   ```

3. Keep the file in place. Do not delete it.

4. Update any configurations in `configs/` that reference the rule.

---

## Writing Test Cases

Every rule with `Status: Published` must have test cases. Test cases live
in the `tests/` directory.

### Test case format

```yaml
# tests/CORE-000005.yaml
rule_id: CORE-000005
tests:
  - name: "Placebo with zero dose passes"
    data:
      EX:
        - {EXTRT: "PLACEBO", EXDOSE: 0}
    expect: pass

  - name: "Placebo with non-zero dose fails"
    data:
      EX:
        - {EXTRT: "PLACEBO", EXDOSE: 5}
    expect: fail
    expected_message: "EXTRT is PLACEBO, but EXDOSE is not equal to 0."

  - name: "Non-placebo treatment is not checked"
    data:
      EX:
        - {EXTRT: "ASPIRIN", EXDOSE: 100}
    expect: pass
```

### Test case requirements

- At least one **pass** case and one **fail** case per rule.
- At least one **edge case** (null values, empty strings, boundary values).
- For rules with conditions, test both the condition-met and
  condition-not-met paths.

---

## Controlled Terminology Updates

CT updates are handled via the fetch script:

```bash
Rscript inst/scripts/fetch-ct.R
```

Do not manually edit files in `ct/`. If a CT value is missing or incorrect:

1. Verify against the NCI EVS browser:
   https://nciterms.nci.nih.gov/ncitbrowser/
2. If the value is genuinely missing from NCI EVS, open an issue.
3. If it is a herald mapping error, fix the fetch script.

---

## Configuration Changes

Configuration files in `configs/` control which rules are active for each
agency profile. Changes to configurations require the same review process
as rule changes.

When adding a new rule, ensure it is included in the appropriate
configuration. When deprecating a rule, update all configurations that
reference it.

---

## Pull Request Process

1. **One logical change per PR.** Do not combine unrelated rule additions
   or modifications.

2. **Branch naming:**
   - `feature/add-<rule-id>` for new rules
   - `fix/<rule-id>-<brief-description>` for corrections
   - `chore/update-ct-<date>` for CT updates

3. **PR title format:**
   - `Add CORE-000350: Variable length exceeds allowed maximum`
   - `Fix FDAB042: Correct domain scope to include SUPPQUAL`
   - `Deprecate FDAB042: Superseded by CORE-000350`

4. **PR description must include:**
   - Source authority and document reference
   - Rationale for the change
   - Link to upstream source if applicable
   - Impact assessment (which submissions are affected)

5. **CI validation** must pass before review.

6. **Two approvals required** for any rule change. At least one reviewer
   must have domain expertise in the relevant standard (SDTM, ADaM,
   Define-XML, or the regulatory authority).

---

## PR Review Checklist

Reviewers must verify each item before approving:

### Schema and Format

- [ ] YAML parses without errors
- [ ] All required fields are present (see [RULE_SCHEMA.md](RULE_SCHEMA.md))
- [ ] Rule ID matches the filename
- [ ] Rule ID follows the correct naming convention for its authority
- [ ] No duplicate rule IDs in the repository

### Content Accuracy

- [ ] Description accurately reflects the validation check
- [ ] Outcome message is clear and actionable
- [ ] Authorities section cites the correct source document
- [ ] Citation text matches the source document verbatim
- [ ] Document version, section, and item numbers are correct
- [ ] Scope (Classes, Domains, Use Case) is correct

### Check Logic

- [ ] Check operators are valid (see operator list in RULE_SCHEMA.md)
- [ ] Check logic correctly implements the rule description
- [ ] Conditions and value comparisons are correct
- [ ] Edge cases are handled (null values, missing variables)
- [ ] Sensitivity level is appropriate (Record, Dataset, or Study)

### Test Cases

- [ ] At least one pass and one fail test case
- [ ] Edge cases are tested (nulls, empty strings, boundaries)
- [ ] Condition paths are tested (condition-met and condition-not-met)
- [ ] Expected messages match the Outcome.Message

### Backward Compatibility

- [ ] Existing rules are not broken by this change
- [ ] Version is incremented for modified rules
- [ ] Deprecated rules have the Deprecated section
- [ ] Configurations are updated if necessary

### Regulatory Traceability

- [ ] The source document is listed in `inst/sources.json`
- [ ] The rule can be traced to a specific guidance paragraph or table row
- [ ] Any deviations from the source are documented and justified

---

## Commit Conventions

- Use imperative present tense: `Add FDAB087` not `Added FDAB087`
- Prefix with action: `Add`, `Fix`, `Deprecate`, `Update`
- Reference the rule ID in the commit message

Examples:

```
Add CORE-000350: Variable length exceeds allowed maximum
Fix FDAB042: Correct domain scope to include SUPPQUAL domains
Deprecate FDAB042: Superseded by CORE-000350
Update CT: March 2026 NCI EVS release
```

---

## Reporting Issues

If you find an incorrect rule or a missing validation check:

1. **Search existing issues** to avoid duplicates.
2. **Open an issue** with the following information:
   - Rule ID (if modifying an existing rule)
   - Source document and section
   - Expected behavior vs. current behavior
   - Example data that demonstrates the issue
3. **Label the issue** with the appropriate authority tag (`fda`, `pmda`,
   `cdisc`, `adam`, `sdtm`).

---

## Code of Conduct

All contributors are expected to be professional, constructive, and
focused on regulatory accuracy. Disagreements about rule interpretation
should be resolved by reference to the source documents.

---

## Questions?

If you are unsure about the correct interpretation of a regulatory rule,
open a discussion issue. Do not guess. Incorrect validation rules can
block legitimate submissions or, worse, allow non-conformant data to
pass review.
