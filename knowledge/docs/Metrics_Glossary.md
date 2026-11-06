# Juniper Valley Health: Revenue Cycle and Quality Metrics Glossary

Owner: Office of Analytics and Quality
Audience: analysts, finance, quality, and anyone publishing a metric outside their team

This glossary is the system of record for how Juniper Valley Health calculates its
headline revenue-cycle and quality metrics. When a dashboard, report, or ad hoc
analysis disagrees with a definition here, the glossary wins.

All tables referenced below live in `JUNIPER_HEALTH.ANALYTICS`. Unless a report says
otherwise, every metric is calculated over **all available history**, with no rolling
window and no minimum sample size.

---

## Clean Claim Rate

**What it measures.** The share of claims that went through the payer cleanly: accepted
the first time, paid, and never denied along the way.

**Definition.** A claim is clean only when **all three** of these are true:

1. `CLAIMS.submission_count = 1`, so it was accepted on its first submission
2. `CLAIMS.claim_status = 'Paid'`
3. The claim has **no row** in `DENIALS`

```
Clean Claim Rate = clean claims / all claims
```

**Common mistakes.**

- Using `submission_count = 1` on its own. That's the industry "first pass" rate, and
  it's not ours. A claim that was denied, appealed, and eventually paid without being
  resubmitted still has `submission_count = 1`, and it is not clean.
- Treating `Pending` or `Partially Paid` claims as clean. Only `Paid` counts.
- Ranking payers on first-pass acceptance. Payer comparisons for contract reviews always
  use the clean claim rate.

The saved query `clean_claim_rate_by_payer.sql` is the reference implementation.

---

## Denial Rate

**Definition.** Distinct claims with at least one row in `DENIALS`, divided by all claims.

`DENIALS` is recorded at **claim line** grain, so one claim can have several rows.
Always count `DISTINCT claim_id`. Counting rows overstates the rate.

When a program asks for a facility's denial rate, the numerator and denominator are both
limited to claims for encounters at that facility.

---

## 30-Day Readmission Rate

**What it measures.** How often patients come back unplanned within 30 days of an
inpatient stay. This is the figure we report to the board and benchmark against the CMS
penalty threshold, so the definition is strict.

### Denominator: eligible index admissions

Start from the base population, then apply the exclusions.

Base population, all of which must hold:

1. `ENCOUNTERS.encounter_type = 'Inpatient'`
2. `ENCOUNTERS.status <> 'Cancelled'`
3. `ENCOUNTERS.discharge_date IS NOT NULL`

Then **exclude** the admission from the denominator when either is true:

4. The patient was **under 18** at admission. Age is
   `DATEDIFF('year', PATIENTS.dob, ENCOUNTERS.admit_date)`.
5. The admission is **obstetric**: any row in `DIAGNOSES` for that encounter has an
   `icd10_code` starting with `O`. There is no obstetric flag in the data; the ICD-10
   chapter is the only signal.

What's left are the **eligible index admissions**.

### Numerator: qualifying readmissions

Count rows in `READMISSIONS` where all of these hold:

1. `is_planned = FALSE`. Planned readmissions, such as a scheduled second-stage
   procedure, never count.
2. `days_to_readmit <= 30`
3. `index_encounter_id` is an **eligible index admission** from the denominator above.

The third rule is the one people miss. `READMISSIONS` records events against every
inpatient admission, including obstetric and pediatric stays that the denominator
removes. If you count those events, the rate is inflated even though the denominator is
right.

Planned readmissions are a **numerator** rule only. Don't drop index admissions from the
denominator because they were followed by a planned readmission.

```
30-Day Readmission Rate = qualifying readmissions / eligible index admissions
```

### Reference SQL

```sql
WITH obstetric AS (
    SELECT DISTINCT encounter_id
    FROM JUNIPER_HEALTH.ANALYTICS.DIAGNOSES
    WHERE icd10_code LIKE 'O%'
),
eligible AS (
    SELECT e.encounter_id, e.facility_id
    FROM JUNIPER_HEALTH.ANALYTICS.ENCOUNTERS e
    JOIN JUNIPER_HEALTH.ANALYTICS.PATIENTS p ON p.patient_id = e.patient_id
    WHERE e.encounter_type = 'Inpatient'
      AND e.status <> 'Cancelled'
      AND e.discharge_date IS NOT NULL
      AND DATEDIFF('year', p.dob, e.admit_date) >= 18
      AND e.encounter_id NOT IN (SELECT encounter_id FROM obstetric)
)
SELECT
    COUNT(DISTINCT r.readmission_id) AS qualifying_readmissions,
    (SELECT COUNT(*) FROM eligible)  AS eligible_index_admissions
FROM JUNIPER_HEALTH.ANALYTICS.READMISSIONS r
JOIN eligible el ON el.encounter_id = r.index_encounter_id
WHERE r.is_planned = FALSE
  AND r.days_to_readmit <= 30;
```

**Benchmark.** CMS treats a rate above 18% as penalty territory. Never publish a
readmission rate that wasn't calculated this way. The Data Release Policy requires the
certified figure for anything that leaves the organization.

---

## Experience Score

**Definition.** The average of `PATIENT_SURVEYS.overall_rating`, multiplied by 10, so it
reads on a 0 to 100 scale.

`overall_rating` is collected on a 1 to 10 scale. Reports, program thresholds, and board
materials always use the 0 to 100 Experience Score, never the raw average.

For a facility, use the surveys where `PATIENT_SURVEYS.facility_id` is that facility.

---

## Related programs

- **BEACON** facility designation: see `BEACON_Facility_Designation.md`
- **Project Tailwind** billing initiative: see `Project_Tailwind.md`
- Sending any metric outside Juniper Valley Health: see
  `External_Data_Release_Policy.md`
