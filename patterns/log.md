# Haskell Patterns Update Log

## 2026-10-02
* **Navigation**: getting-started routes new CLI configuration to `mori://shinzui/keiro-runtime-patterns/docs/config-settei-cli-standard` and kit distribution to the rewritten baikai-kit integration pattern; removed routes to obsolete Dhall and Claude subprocess documents

## 2026-09-19
* **Migration**: Moved the bundle to OKF v0.2 and okf-profiles v0.18.0: added `generated` provenance from each document's timestamp and Git author, and normalized `timestamp` and review `document_timestamp` values to UTC without changing their instants

## 2026-07-30
* **Navigation**: Added black-box API integration testing with Hurl to the task-oriented API route

## 2026-07-24
* **Rename**: getting-started now routes to the renamed RFC 9457 problem-details standard (formerly rfc7807-problem-details)
* **Correction**: Made reviews optional and removed migration-time metadata approvals that could be mistaken for substantive review
* **Migration**: Adopted the OKF documentation pattern-catalog profile, task-oriented navigation, generated indexes, scoped logs, and review provenance
