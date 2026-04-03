# Define-XML v2.1 Spec Validation Rules -- Traceability

Rules derived from the CDISC Define-XML v2.1 Specification (Final, 2019-05-15)
and aligned with Pinnacle 21 Enterprise define validation rules.

## Rule → Spec Section Mapping

| Rules | Spec Section | Topic | P21 Alignment |
|---|---|---|---|
| DD0001-DD0005 | 5.3.3, 5.3.4, 5.3.5 | ODM root, Study, GlobalVariables, MetaDataVersion | DD0006, DD0007 |
| DD0006-DD0007 | 5.3.11, 5.3.9.1 | ItemGroupDef required attrs, Description | DD0057 |
| DD0008-DD0010 | 5.3.11.2 | def:Class, def:SubClass allowable values | DD0055 |
| DD0011 | 5.3.11 | def:Structure required | -- |
| DD0012-DD0016 | 4.1.1, 5.3.6.1 | def:Standard Name/Type/Version allowable values | DD0148 |
| DD0017 | 5.3.9.2 | ItemRef KeySequence requirement | DD0040 |
| DD0018-DD0019 | 5.3.11 | Repeating, IsReferenceData business rules | OD0072 |
| DD0020 | 5.3.11 | Purpose: Tabulation vs Analysis | -- |
| DD0021-DD0022 | 5.3.12, 5.3.9.1 | ItemDef Name, Description required | DD0057 |
| DD0023-DD0028 | 4.3.1, 5.3.12 | DataType, Length, SignificantDigits rules | DD0068, DD0123 |
| DD0029 | 5.3.9.2 | Mandatory attribute | -- |
| DD0030-DD0038 | 4.3.2, 5.3.12.3, 4.9 | Origin/Source/Traceability rules | DD0072, DD0109 |
| DD0039-DD0040 | 5.3.9.2, 5.3.11 | OrderNumber, cross-ref to ItemGroupDef | OD0046 |
| DD0041-DD0047 | 5.3.9, 5.3.10, 4.5 | ValueListDef, WhereClauseDef rules | DD0001 |
| DD0048-DD0055 | 5.3.13, 4.4 | CodeList, EnumeratedItem, CodeListItem rules | DD0024, DD0031, DD0032, DD0033 |
| DD0056-DD0059 | 5.3.14 | MethodDef rules | DD0104 |
| DD0060-DD0063 | 5.3.15, 5.3.16 | CommentDef, def:leaf rules | DD0071 |
| DD0064-DD0073 | 3.5 (OIDs/Defs-and-Refs) | Cross-reference integrity between sheets | OD0046, OD0048, DD0071 |
| DD0074-DD0077 | 3.5 (OIDs) | Orphan detection | DD0079, DD0080, DD0082 |
| DD0078-DD0081 | ARM 1.0 | Analysis Results Metadata rules | DD0091, DD0096, DD0099, DD0100 |
| DD0082-DD0085 | 4.3.2, 5.3.12, 5.3.13, 4.1.1 | P21 alignment (origin consistency, datatype match, CT) | DD0029, OD0075, OD0080, DD0148 |

## Quarterly Refresh Process

When CDISC publishes a new Define-XML specification version:

1. Diff the new spec against the current version, section by section
2. Use the table above to identify which DD rules are affected
3. For changed requirements: increment `version` in YAML, update provenance
4. For new requirements: create new DD rules with next available ID
5. For removed requirements: set `status: Deprecated` with reason
6. Update: herald-master-rules.csv, configs/*.json, manifest.json, CHANGELOG.md

## Source Documents

- CDISC Define-XML v2.1 Specification (Final, 2019-05-15)
- P21 Enterprise define_rules.xlsx (31 DD rules + 6 OD rules)
- Define-XML v2.1 XML Schema (define2-1-0.xsd)
