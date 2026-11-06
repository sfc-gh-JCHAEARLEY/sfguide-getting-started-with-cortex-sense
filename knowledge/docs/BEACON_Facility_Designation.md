# BEACON Facility Designation

Owner: Office of Analytics and Quality
Status: Active

## What BEACON is

BEACON stands for **Balanced Excellence Across Clinical Outcomes and Net revenue**. It's
Juniper Valley Health's internal recognition for facilities that are strong on patient
experience, clinical quality, and revenue integrity at the same time.

The point of the designation is balance. A facility with outstanding patient surveys and a
poor readmission record doesn't qualify, and neither does one with clean finances and
unhappy patients. Recognized facilities get first call on capital requests and are used as
peer mentors for the rest of the system.

## Who is eligible

BEACON applies to facilities that provide inpatient care, meaning any facility with at
least one eligible index admission as defined in the Metrics Glossary. Clinics without
inpatient beds aren't evaluated.

## Criteria

A facility is BEACON-designated only when it meets **all three** criteria:

| Criterion | Threshold | Definition |
|---|---|---|
| Experience Score | **85 or higher** | Metrics Glossary, Experience Score (0 to 100 scale) |
| 30-Day Readmission Rate | **below 8%** | Metrics Glossary, 30-Day Readmission Rate, calculated for the facility's own eligible index admissions |
| Denial Rate | **below 4%** | Metrics Glossary, Denial Rate, distinct denied claims over all claims at the facility |

Meeting two of three is not a partial designation. A facility that misses any one
criterion is not BEACON.

## How it's measured

- Use **all available history**. There is no rolling window.
- There are no minimum volume floors on surveys, admissions, or claims.
- Each criterion uses the glossary definition exactly. In particular, the readmission
  criterion uses the house 30-Day Readmission Rate, with its exclusions, not a raw count
  of readmission events.

The saved query `beacon_scorecard.sql` produces the scorecard for every eligible
facility, including which criteria each one passes. When someone asks which facilities
are close, look for facilities that pass two criteria and miss one.

## Questions

Contact the Office of Analytics and Quality at analytics@junipervalley.example.
