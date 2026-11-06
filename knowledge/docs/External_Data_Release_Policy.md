# External Data Release Policy

Owner: Data Governance Council
Applies to: every employee, contractor, and system that shares Juniper Valley Health data

## Release tiers

| Tier | Audience | Examples | Approval |
|---|---|---|---|
| Tier 1 | Internal, same team | Working analyses, team dashboards | None |
| Tier 2 | Internal, across teams | Board packs, system-wide scorecards | Data owner |
| Tier 3 | **Anyone outside Juniper Valley Health** | Partners, vendors, researchers, benchmarking groups, payers | **Data Governance Council, in writing** |

A request from an outside organization is always Tier 3, even if we have a contract,
data use agreement, or Business Associate Agreement (BAA) with them.

## Tier 3 rules for quality metrics

Quality metrics such as the 30-Day Readmission Rate can be released externally only when
**all four** of these conditions are met. Meeting three of four is not a partial pass.

### 1. Facility level only

Release aggregates at facility level. Never release patient-level or encounter-level rows.
Provider-level results need a separate approval and aren't covered by this policy.

Facilities that don't provide inpatient care have no readmission rate and are left out of
readmission releases entirely.

### 2. Small-cell suppression

Suppress any facility whose metric rests on fewer than **20 eligible index admissions**,
using the Metrics Glossary definition of an eligible index admission. Show the value as
the word `suppressed`, not as zero and not as a blank.

Our threshold is deliberately stricter than the common HHS convention of 11. Several of
our facilities are small, and a rate on a low denominator can be traced back to individual
patients.

### 3. Blinded facility names

Replace facility names with blinded codes (`JVH-A`, `JVH-B`, and so on) assigned by the
Data Governance Council. Don't include city, bed count, or anything else that identifies a
facility.

### 4. Written approval

Get written approval from the **Data Governance Council** before anything is sent. Email
dgc@junipervalley.example with the request, the recipient, the fields, and a sample of the
output. Allow **10 business days** from a complete request.

## What to send

Send the **certified** figure, calculated exactly as the Metrics Glossary defines it. Don't
send a recomputation that uses a different method, even if it looks close.

## Things that don't authorize a release

- **A BAA.** A Business Associate Agreement permits the relationship. It doesn't approve
  any specific release, and it doesn't replace Data Governance Council approval.
- **De-identification on its own.** Facility-level data with no patient identifiers is
  still Tier 3 when it leaves the organization.
- **A previous approval.** Each release needs its own approval, even when it repeats an
  earlier one.
