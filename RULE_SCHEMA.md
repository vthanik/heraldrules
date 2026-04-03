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
- [Source](#source)
- [Deprecated Section](#deprecated-section)
- [Comment Header](#comment-header)
- [Complete Examples](#complete-examples)

---

## Overview

Each rule is a single YAML file. The filename must match the rule ID
(e.g., `CORE-000005.yaml`, `FDAB001.yaml`). Rules are organized by
source authority in the `engines/` directory.

---

## Top-Level Fields

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
| CDISC CORE | `CORE-NNNNNN` | `CORE-000005` | `engines/core/` |
| FDA Business Rules | `FDABXXX` | `FDAB001` | `engines/fda/` |
| PMDA Validation | `PMDAXXX` | `PMDA001` | `engines/pmda/` |
| herald custom | `HRLD-XXXX` | `HRLD-0001` | `engines/core/` |

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
| `max_length` | `value` (integer) | Variable length does not exceed the given maximum |
| `min_length` | `value` (integer) | Variable length is at least the given minimum |

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
| `is_date` | none | Variable values conform to ISO 8601 date format |
| `is_datetime` | none | Variable values conform to ISO 8601 datetime format |

### Cross-variable operators

| Operator | Arguments | Description |
|----------|-----------|-------------|
| `equal_to_variable` | `value` (variable name) | Variable equals another variable in the same record |
| `less_than_variable` | `value` (variable name) | Variable is less than another variable |
| `greater_than_variable` | `value` (variable name) | Variable is greater than another variable |
| `less_than_or_equal_to_variable` | `value` (variable name) | Variable is <= another variable |
| `greater_than_or_equal_to_variable` | `value` (variable name) | Variable is >= another variable |

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
