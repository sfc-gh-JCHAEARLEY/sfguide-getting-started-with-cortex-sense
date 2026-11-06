-- 30-Day Readmission Rate by facility, with a system-wide total
-- Owner: Office of Analytics and Quality. Feeds the monthly quality board pack.
-- Definition: Metrics Glossary, 30-Day Readmission Rate.
--   Denominator: completed inpatient stays (not cancelled, discharged), excluding
--                patients under 18 and obstetric admissions (any ICD-10 code 'O%').
--   Numerator:   unplanned readmissions within 30 days whose index admission is eligible.

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
),
qualifying AS (
    SELECT r.index_encounter_id
    FROM JUNIPER_HEALTH.ANALYTICS.READMISSIONS r
    WHERE r.is_planned = FALSE
      AND r.days_to_readmit <= 30
)
SELECT
    COALESCE(f.facility_name, 'All facilities') AS facility_name,
    COUNT(DISTINCT el.encounter_id) AS eligible_index_admissions,
    COUNT(q.index_encounter_id) AS qualifying_readmissions,
    ROUND(100 * qualifying_readmissions / eligible_index_admissions, 1) AS readmission_rate_pct
FROM eligible el
JOIN JUNIPER_HEALTH.ANALYTICS.FACILITIES f ON f.facility_id = el.facility_id
LEFT JOIN qualifying q ON q.index_encounter_id = el.encounter_id
GROUP BY ROLLUP (f.facility_name)
ORDER BY f.facility_name NULLS LAST;
