# Rule YAML Schema

This document defines the complete YAML schema for herald validation rules.
All rule files in `engines/` must conform to this schema.

## Table of Contents

- [Overview](#overview)
- [Top-Level Fields](#top-level-fields)
- [Core Section](#core-section)
- [Description](#description)
- [Executability](#executability)
- [Check Section](#check-section)
- [Operators](#operators)
- [Outcome Section](#outcome-section)
- [Rule Type](#rule-type)
- [Scope Section](#scope-section)
- [Sensitivity](#sensitivity)
- [Authorities Section](#authorities-section)
- [Herald Metadata Block](#herald-metadata-block)
- [Source](#source)
- [Deprecated Section](#deprecated-section)
- [Comment Header](#comment-header)
- [Embedded Tests](#embedded-tests)
- [Complete Examples](#complete-examples)

---

## Overview

Each rule is a single YAML file. The filename must match the rule ID
(e.g., `CORE-000005.yaml`, `FDAB001.yaml`). Rules are organized by
source authority in the `engines/` directory.

Two YAML schemas coexist in this repository:

- **PascalCase** (CDISC CORE format) — used in `engines/cdisc/` and `engines/fda/`
- **lowercase** (herald format) — used in `engines/pmda/`, `engines/ct/`, and `engines/herald/`

Both schemas are documented below.

---

## Top-Level Fields

### PascalCase schema (engines/cdisc/, engines/fda/)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Core` | object | Yes | Rule identity and status |
| `Description` | string | Yes | Human-readable description of the rule |
| `Executability` | string | No | Whether the rule can be executed programmatically |
| `Check` | object or array | Yes | The validation logic (empty `[]` for Reference rules) |
| `Outcome` | object | Yes | Message and output variables |
| `Rule Type` | string | Yes | Category of the validation check |
| `Scope` | object | No | Which classes, domains, and use cases the rule applies to |
| `Sensitivity` | string | Yes | Granularity of the check result |
| `Authorities` | array | No | Regulatory citations |
| `Source` | string | No | Short source reference (used by FDA/PMDA rules) |
| `Deprecated` | object | No | Deprecation metadata (only for deprecated rules) |
| `herald` | object | No | Herald-specific metadata (ig_versions, source, catalogs, fetched) |
| `tests` | array | Req. for Published | Embedded test cases (see [Embedded Tests](#embedded-tests)) |

### Lowercase schema (engines/pmda/, engines/ct/, engines/herald/)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique rule identifier |
| `version` | integer | Yes | Rule version (increment on modification) |
| `status` | string | Yes | Lifecycle status (`Published`, `Reference`, `Draft`, `Deprecated`) |
| `standard` | string | No | Applicable standard (`SDTM`, `ADaM`, `Define-XML`) |
| `category` | string | No | Rule category for grouping |
| `sensitivity` | string | Yes | Granularity of the check result |
| `executability` | string | No | `Fully Executable`, `Partially Executable`, or `Hardcoded` |
| `description` | string | Yes | Human-readable description of the rule |
| `check` | object | Yes | The validation logic |
| `outcome` | object | Yes | Message and severity |
| `provenance` | object | No | Source document, authority, section reference |
| `deprecated` | object | No | Deprecation metadata |
| `tests` | array | Req. for Published | Embedded test cases |

#### Lowercase `outcome` fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `message` | string | Yes | Human-readable error/warning message |
| `severity` | string | No | `Error` or `Warning` (default: `Error`) |

#### Lowercase `provenance` fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source_doc` | string | Yes | Source document name |
| `authority` | string | Yes | Issuing authority (`CDISC`, `FDA`, `PMDA`, `Herald`) |
| `section` | string | No | Section or rule number in the source document |
| `standard` | string | No | Standard name (overrides top-level `standard`) |

---

## Core Section

The `Core` section identifies the rule and its lifecycle status.

```yaml
Core:
  Id: CORE-000005
  Status: Published
  Version: '1'
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Id` | string | Yes | Unique rule identifier |
| `Status` | string | Yes | Lifecycle status |
| `Version` | string | Yes | Rule version (incremented on modification) |

### Status Values

| Status | Meaning |
|--------|---------|
| `Published` | Rule is active and executable. Has a `Check` section with logic. |
| `Reference` | Rule is metadata only. `Check` is empty (`[]`). Not executed at runtime. |
| `Draft` | Rule is under development. Not included in releases. |
| `Deprecated` | Rule is retired. Not executed. Must have a `Deprecated` section. |

### Id Conventions

| Authority | Pattern | Example | Directory |
|-----------|---------|---------|-----------|
| CDISC CORE | `CORE-NNNNNN` | `CORE-000005` | `engines/cdisc/` |
| FDA Business Rules | `FDABXXX` | `FDAB001` | `engines/fda/` |
| PMDA Validation | `PMDAXXX` | `PMDA001` | `engines/pmda/` |
| herald custom (YAML) | `HRL-{CAT}-NNN` | `HRL-AD-001` | `engines/herald/` |
| herald custom (hardcoded) | `HRL-{CAT}-NNN` | `HRL-VAR-001` | `engines/herald/` |
| herald CT per-codelist | `HRL-CT-NNNN` | `HRL-CT-0001` | `engines/ct/` |
| herald Define-XML spec | `DDNNNN` | `DD0001` | `engines/herald/define/` |

---

## Description

A single string that describes what the rule checks in plain language.

```yaml
Description: When EXTRT is PLACEBO, EXDOSE must equal 0
```

The description should be concise and unambiguous. It should describe
the **expected valid state**, not the error condition. For example:

- Good: `When EXTRT is PLACEBO, EXDOSE must equal 0`
- Avoid: `EXDOSE is wrong when EXTRT is PLACEBO`

For error-raising rules, the description may be phrased as:

```yaml
Description: Raise an error when SESTDTC is null.
```

---

## Executability

Indicates whether the rule can be programmatically executed by the
herald engine.

```yaml
Executability: Fully Executable
```

### Values

| Value | Meaning |
|-------|---------|
| `Fully Executable` | The `Check` section completely implements the rule logic. |
| `Partially Executable` | The `Check` section implements part of the rule. Manual review may be needed. |
| `Hardcoded` | Rule logic is implemented in R code (`R/val-checks.R`). The YAML is a reference stub only. |
| Not present | The rule is `Reference` status and has no check logic. |

---

## Check Section

The `Check` section defines the validation logic using a declarative
operator-based syntax.

### Empty check (Reference rules)

```yaml
Check: []
```

### Simple check (single condition)

```yaml
Check:
  all:
    - name: SESTDTC
      operator: empty
```

### Compound check (multiple conditions)

```yaml
Check:
  all:
    - name: EXTRT
      operator: equal_to
      value: PLACEBO
    - name: EXDOSE
      operator: not_equal_to
      value: 0
```

### Check with `any` (OR logic)

```yaml
Check:
  any:
    - name: AESTDTC
      operator: empty
    - name: AEENDTC
      operator: empty
```

### Check with nested `all` and `any`

```yaml
Check:
  all:
    - name: DOMAIN
      operator: equal_to
      value: AE
    - any:
        - name: AESTDTC
          operator: empty
        - name: AETERM
          operator: empty
```

### Condition elements

Each element in a check list is a **condition** with the following
fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Variable name to check. Use `--` prefix for class-level variables (e.g., `--STDTC`). |
| `operator` | string | Yes | The comparison operator (see [Operators](#operators)). |
| `value` | string, number, or array | Depends on operator | The comparison value. Not required for unary operators like `empty` or `exists`. |

---

## Operators

The following operators are supported in `Check` conditions:

### Existence operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `empty` | none | Variable value is null, NA, or empty string |
| `not_empty` | none | Variable value is not null, not NA, and not empty string |
| `exists` | none | Variable exists in the dataset (column is present) |
| `not_exists` | none | Variable does not exist in the dataset |

### Comparison operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `equal_to` | `value` | Variable equals the given value |
| `not_equal_to` | `value` | Variable does not equal the given value |
| `less_than` | `value` | Variable is less than the given value |
| `less_than_or_equal_to` | `value` | Variable is less than or equal to the given value |
| `greater_than` | `value` | Variable is greater than the given value |
| `greater_than_or_equal_to` | `value` | Variable is greater than or equal to the given value |

### String operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `matches_regex` | `value` (regex) | Variable matches the regular expression |
| `not_matches_regex` | `value` (regex) | Variable does not match the regular expression |
| `starts_with` | `value` | Variable starts with the given string |
| `ends_with` | `value` | Variable ends with the given string |
| `contains` | `value` | Variable contains the given substring |
| `not_contains` | `value` | Variable does not contain the given substring |
| `is_uppercase` | none | Variable value is entirely uppercase |
| `is_lowercase` | none | Variable value is entirely lowercase |

### Set operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `in` | `value` (array) | Variable value is in the given set |
| `not_in` | `value` (array) | Variable value is not in the given set |
| `is_unique` | none | Variable values are unique within the dataset |
| `not_unique` | none | Variable values are not unique (duplicates exist) |

### Type operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `is_integer` | none | Variable values are integers |
| `is_numeric` | none | Variable values are numeric |
| `not_numeric` | none | Variable value is not numeric (e.g., letters mixed with digits) |
| `not_character` | none | Variable value is not character type |
| `is_date` | none | Variable values conform to ISO 8601 date format |
| `is_datetime` | none | Variable values conform to ISO 8601 datetime format |

### String length operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `longer_than` | `value` (integer) | Variable value length exceeds N characters |
| `max_length` | `value` (integer) | Variable length does not exceed the given maximum |
| `min_length` | `value` (integer) | Variable length is at least the given minimum |

### String pattern operators (extended)

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `matches_regex` | `value` (regex) | Variable matches the regular expression |
| `not_matches_regex` | `value` (regex) | Variable does not match the regular expression |
| `contains_control_characters` | none | Variable contains non-printable ASCII (< 32 or = 127) |

### Cross-variable operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `equal_to_variable` | `value` (variable name) | Variable equals another variable in the same record |
| `less_than_variable` | `value` (variable name) | Variable is less than another variable |
| `greater_than_variable` | `value` (variable name) | Variable is greater than another variable |
| `less_than_or_equal_to_variable` | `value` (variable name) | Variable is <= another variable |
| `greater_than_or_equal_to_variable` | `value` (variable name) | Variable is >= another variable |

### Consistency operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `not_consistent_within` | `value` (grouping variable) | Variable is not consistent within groups of the grouping variable |
| `not_consistent_with_variable` | `value` (variable name) | Variable values are inconsistent with the named variable across records |
| `adsl_consistency_check` | `value` (ADSL variable) | Subject-level variable does not match the corresponding ADSL variable |

### Cross-dataset operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `no_matching_record` | `value` (dataset.variable reference) | No matching record exists in the referenced dataset |
| `not_in_define_vlm` | none | QNAM value is not defined in the Define-XML Value Level Metadata |

### Dataset-level operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `has_variable` | `value` (variable name) | Dataset contains the named variable |
| `not_has_variable` | `value` (variable name) | Dataset does not contain the named variable |
| `row_count_greater_than` | `value` (integer) | Dataset has more than N rows |
| `row_count_equal_to` | `value` (integer) | Dataset has exactly N rows |

### Controlled Terminology operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `in_codelist` | `value` (codelist name) | Variable value is in the named CDISC codelist |
| `not_in_codelist` | `value` (codelist name) | Variable value is not in the named codelist |

---

## Outcome Section

The `Outcome` section defines what message is produced when the rule is
triggered (i.e., when the check conditions are met, indicating a
violation).

```yaml
Outcome:
  Message: EXTRT is PLACEBO, but EXDOSE is not equal to 0.
  Output Variables:
    - EXTRT
    - EXDOSE
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Message` | string | Yes | Human-readable error/warning message |
| `Output Variables` | array of strings | No | Variables to include in the output for context |

The message should be specific enough that a programmer can identify
and fix the issue without reading the rule definition.

---

## Rule Type

Categorizes the level at which the rule operates.

```yaml
Rule Type: Record Data
```

### Values

| Value | Description |
|-------|-------------|
| `Record Data` | Checks individual records (rows) in a dataset |
| `Dataset Metadata` | Checks dataset-level properties (labels, variable names) |
| `Value Level Metadata` | Checks value-level metadata in Define-XML |
| `Variable Metadata` | Checks variable-level properties (type, length, label) |
| `Domain Presence` | Checks whether required domains are present |

---

## Scope Section

Defines which classes, domains, and use cases the rule applies to.

```yaml
Scope:
  Classes:
    Include:
      - INTERVENTIONS
      - FINDINGS
  Domains:
    Include:
      - AE
      - CM
    Exclude:
      - SUPPAE
  Use Case: INDH, PROD
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Classes` | object | No | SDTM class filter |
| `Classes.Include` | array | No | Classes the rule applies to |
| `Classes.Exclude` | array | No | Classes the rule does not apply to |
| `Domains` | object | No | Domain filter |
| `Domains.Include` | array | No | Domains the rule applies to. Use `ALL` for all domains. |
| `Domains.Exclude` | array | No | Domains the rule does not apply to |
| `Use Case` | string | No | Comma-separated use case codes |

### Class Values

| Class | Description |
|-------|-------------|
| `INTERVENTIONS` | SDTM Interventions class (EX, CM, SU, etc.) |
| `EVENTS` | SDTM Events class (AE, CE, DS, DV, etc.) |
| `FINDINGS` | SDTM Findings class (LB, VS, EG, etc.) |
| `SPECIAL PURPOSE` | SDTM Special Purpose class (DM, SE, SV) |
| `TRIAL DESIGN` | SDTM Trial Design class (TA, TE, TI, TS, TV) |
| `RELATIONSHIP` | SDTM Relationship datasets (RELREC, SUPP--) |
| `ASSOCIATED PERSONS` | SDTM Associated Persons datasets |
| `DEVICE` | SDTM Device datasets |

### Use Case Codes

| Code | Description |
|------|-------------|
| `INDH` | Individual human clinical trials |
| `PROD` | Production submissions |
| `SEND` | Non-clinical SEND studies |

If `Scope` is not present, the rule applies to all classes and domains.

---

## Sensitivity

Defines the granularity of the rule's output.

```yaml
Sensitivity: Record
```

### Values

| Value | Description |
|-------|-------------|
| `Record` | One finding per non-conformant record (row) |
| `Dataset` | One finding per non-conformant dataset |
| `Study` | One finding per study |

---

## Authorities Section

Lists the regulatory authorities and standards that define the rule.
This section provides traceability from the rule back to its source
document.

```yaml
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
                Item: Assumption 2b
```

### Authorities Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Organization` | string | Yes | The regulatory or standards organization |
| `Standards` | array | No | Standards that contain this rule |

### Standards Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Name` | string | Yes | Standard name (e.g., `SDTMIG`, `ADaMIG`, `TIG`) |
| `Version` | string | Yes | Standard version |
| `Substandard` | string | No | Sub-standard within the standard (e.g., `SDTM` within TIG) |
| `References` | array | Yes | Specific references within this standard |

### References Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Origin` | string | Yes | Origin of the rule (e.g., `SDTM and SDTMIG Conformance Rules`) |
| `Rule Identifier` | object | No | Original rule ID in the source standard |
| `Rule Identifier.Id` | string | Yes | Source rule ID (e.g., `CG0102`) |
| `Rule Identifier.Version` | string | Yes | Source rule version |
| `Version` | string | No | Version of the conformance rule set |
| `Citations` | array | Yes | Specific citations from the document |

### Citations Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Cited Guidance` | string | Yes | Verbatim or near-verbatim text from the source |
| `Document` | string | Yes | Document name and version |
| `Section` | string | No | Section number or name |
| `Item` | string | No | Specific item within the section |

### Organization Values

| Organization | Description |
|--------------|-------------|
| `CDISC` | CDISC standards (SDTM, ADaM, SEND, Define-XML) |
| `FDA` | U.S. Food and Drug Administration |
| `PMDA` | Japan Pharmaceuticals and Medical Devices Agency |
| `EMA` | European Medicines Agency |

---

## Herald Metadata Block

The `herald:` block (PascalCase rules) or equivalent top-level fields
(lowercase rules) carries herald-specific metadata used during config
assembly and provenance tracking. This block is **not** part of the
original CDISC CORE schema — it is added by herald to CDISC and ADaM
rules during the fetch/transform pipeline.

```yaml
herald:
  ig_versions: ["1.2"]          # ADaM IG version(s) this rule applies to
  source: Herald-originated (ADaM-IG v1.2 gap-fill)
  catalogs:
    - ADaMIG 1.2
  fetched: '2026-04-12'
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ig_versions` | array of strings | No | ADaM IG versions this rule applies to. Null/omitted = applies to all versions (SDTM/SEND CORE rules). Used by `build-configs.R` (ADR-002, ADR-003). |
| `source` | string | No | Free-text description of where the rule came from |
| `catalogs` | array of strings | No | Catalog name(s) that include this rule |
| `fetched` | string (YYYY-MM-DD) | No | Date the rule was last fetched or created |

**ADR-002:** Version scope lives in `herald.ig_versions` on each rule YAML.
**ADR-003:** Later version is a superset — a rule tagged `["1.1"]` is included in both the 1.1 and 1.2 configs.

---

## Source

A short string identifying the source of the rule. Used primarily by
FDA and PMDA rules that do not have a full `Authorities` section.

```yaml
Source: FDA Business Rules v1.5
```

---

## Deprecated Section

Present only on rules with `Status: Deprecated`. Documents why the
rule was retired and what replaced it.

```yaml
Deprecated:
  Date: 2026-04-01
  Reason: Superseded by CORE-000350
  Replaced_By: CORE-000350
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Date` | string (YYYY-MM-DD) | Yes | Date the rule was deprecated |
| `Reason` | string | Yes | Why the rule was deprecated |
| `Replaced_By` | string | No | Rule ID of the replacement rule, if any |

---

## Comment Header

By convention, each YAML file begins with comment lines that summarize
the rule in a human-scannable format:

```yaml
# Variable: EXDOSE
# Condition: EXTRT = 'PLACEBO'
# Rule: EXDOSE = 0
```

These comments are not parsed by the engine but help with quick
identification when browsing rule files.

### Comment fields

| Comment | Description |
|---------|-------------|
| `# Variable:` | The primary variable being checked |
| `# Condition:` | Any precondition that must be true for the check to apply |
| `# Rule:` | The validation rule expressed as a simple statement |

---

## Embedded Tests

Every rule with `Status: Published` (or `status: Published`) must include
a `tests:` block at the end of the YAML file. Tests are embedded directly
in the rule file — no separate test files are used.

### Requirements

- At least one `type: positive` test (`expected_findings: 0`) — valid data passes.
- At least one `type: negative` test (`expected_findings: N > 0`) — invalid data is caught.
- Use `CDISCPILOT01` as `STUDYID` and realistic `USUBJID` values.
- No `skip: true` — every Published rule must be testable.
- For conditional rules, test both the condition-met and condition-not-met paths.

### Test block format

```yaml
tests:
  - name: "Valid data passes rule"
    type: positive
    datasets:
      EX:
        variables: [STUDYID, USUBJID, EXTRT, EXDOSE]
        records:
          - ["CDISCPILOT01", "01-701-1015", "PLACEBO", "0"]
    expected_findings: 0

  - name: "PLACEBO with non-zero dose fails"
    type: negative
    datasets:
      EX:
        variables: [STUDYID, USUBJID, EXTRT, EXDOSE]
        records:
          - ["CDISCPILOT01", "01-701-1015", "PLACEBO", "5"]
    expected_findings: 1
```

### Test case fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Human-readable description of the test scenario |
| `type` | string | Yes | `positive` (no findings expected) or `negative` (findings expected) |
| `datasets` | object | Yes | Map of domain name → dataset definition |
| `datasets.<DOMAIN>.variables` | array | Yes | Column names in order |
| `datasets.<DOMAIN>.records` | array of arrays | Yes | Data rows, one array per record |
| `expected_findings` | integer | Yes | Number of findings the rule should produce for this input |

---

## Complete Examples

### Example 1: Fully executable CDISC CORE rule

```yaml
# Variable: EXDOSE
# Condition: EXTRT = 'PLACEBO'
# Rule: EXDOSE = 0
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
                  and EXDOSE = "0" (indicating 0 mg of active ingredient was
                  taken or administered).
                Document: SDTMIG v3.4
                Item: Assumption 2b
                Section: 6.1.3.1
Check:
  all:
    - name: EXTRT
      operator: equal_to
      value: PLACEBO
    - name: EXDOSE
      operator: not_equal_to
      value: 0
Core:
  Id: CORE-000005
  Status: Published
  Version: '1'
Description: When EXTRT is PLACEBO, EXDOSE must equal 0
Executability: Fully Executable
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
```

### Example 2: FDA Business Rule (Reference only)

```yaml
Core:
  Id: FDAB001
  Status: Reference
Description: A treatment-emergent flag should be submitted.
Check: []
Outcome:
  Message: A treatment-emergent flag should be submitted.
Rule Type: Record Data
Sensitivity: Record
Authorities:
  - Organization: FDA
Source: FDA Business Rules v1.5
```

### Example 3: Deprecated rule

```yaml
Core:
  Id: FDAB042
  Status: Deprecated
  Version: '2'
Description: Original description of the rule.
Check: []
Outcome:
  Message: Original message.
Rule Type: Record Data
Sensitivity: Record
Deprecated:
  Date: 2026-04-01
  Reason: Superseded by CORE-000350
  Replaced_By: CORE-000350
Authorities:
  - Organization: FDA
Source: FDA Business Rules v1.5
```

### Example 4: Lowercase herald rule (engines/herald/)

```yaml
id: HRL-SD-019
version: 1
status: Published
standard: SDTM
category: Character Encoding
sensitivity: Record
executability: Fully Executable
description: >
  Character variables must not contain non-printable control characters
  (ASCII < 32 or = 127).
check:
  all:
    - name: --ANY--
      operator: contains_control_characters
outcome:
  message: "Character variable contains a non-printable control character."
  severity: Error
provenance:
  source_doc: FDA Technical Conformance Guide v5.0
  authority: FDA
  section: "4.1.2.2"
tests:
  - name: "Clean character data passes"
    type: positive
    datasets:
      AE:
        variables: [STUDYID, USUBJID, AETERM]
        records:
          - ["CDISCPILOT01", "01-701-1015", "HEADACHE"]
    expected_findings: 0
  - name: "Control character in AETERM fails"
    type: negative
    datasets:
      AE:
        variables: [STUDYID, USUBJID, AETERM]
        records:
          - ["CDISCPILOT01", "01-701-1015", "HEAD\u0007ACHE"]
    expected_findings: 1
```

### Example 5: ADaM rule with herald ig_versions metadata

```yaml
Core:
  Id: ADaM-1021
  Status: Published
  Version: '1'
Description: >-
  A variable with a suffix of PFL (parameter-level flag) may have a value
  of Y, N, or null in ADaM-IG v1.2.
Executability: Partially Executable
Check:
  all:
    - name: ANL01FL
      operator: non_empty
    - name: ANL01FL
      operator: not_in
      value: ['Y', 'N']
Outcome:
  Message: '*PFL variable (e.g. ANL01FL) has a value other than Y, N, or null'
Rule_Type: Record Data
Sensitivity: Record
Scope:
  Classes:
    Include:
      - BDS
  Domains:
    Include:
      - ALL
herald:
  ig_versions: ["1.2"]
  source: Herald-originated (ADaM-IG v1.2 gap-fill)
  catalogs:
    - ADaMIG 1.2
  fetched: '2026-04-12'
tests:
  - name: "ANL01FL valid values Y, N, or null"
    type: positive
    datasets:
      ADLB:
        variables: [STUDYID, USUBJID, PARAMCD, ANL01FL]
        records:
          - ["CDISCPILOT01", "01-701-1015", "SODIUM", "Y"]
          - ["CDISCPILOT01", "01-701-1023", "SODIUM", "N"]
          - ["CDISCPILOT01", "01-701-1028", "SODIUM", ""]
    expected_findings: 0
  - name: "ANL01FL has invalid value X"
    type: negative
    datasets:
      ADLB:
        variables: [STUDYID, USUBJID, PARAMCD, ANL01FL]
        records:
          - ["CDISCPILOT01", "01-701-1015", "SODIUM", "X"]
    expected_findings: 1
```
