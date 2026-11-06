-- BEACON designation scorecard
-- Owner: Office of Analytics and Quality.
-- Definition: BEACON_Facility_Designation.md. A facility is designated only when it
-- passes all three criteria, measured over all history with no volume floors:
--   Experience Score >= 85, 30-Day Readmission Rate < 8%, Denial Rate < 4%.

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
readmission AS (
    SELECT
        el.facility_id,
        100 * COUNT(r.readmission_id) / COUNT(DISTINCT el.encounter_id) AS readmission_rate_pct
    FROM eligible el
    LEFT JOIN JUNIPER_HEALTH.ANALYTICS.READMISSIONS r
           ON r.index_encounter_id = el.encounter_id
          AND r.is_planned = FALSE
          AND r.days_to_readmit <= 30
    GROUP BY el.facility_id
),
experience AS (
    SELECT facility_id, 10 * AVG(overall_rating) AS experience_score
    FROM JUNIPER_HEALTH.ANALYTICS.PATIENT_SURVEYS
    GROUP BY facility_id
),
denial AS (
    SELECT
        e.facility_id,
        100 * COUNT(DISTINCT d.claim_id) / COUNT(DISTINCT c.claim_id) AS denial_rate_pct
    FROM JUNIPER_HEALTH.ANALYTICS.CLAIMS c
    JOIN JUNIPER_HEALTH.ANALYTICS.ENCOUNTERS e ON e.encounter_id = c.encounter_id
    LEFT JOIN JUNIPER_HEALTH.ANALYTICS.DENIALS d ON d.claim_id = c.claim_id
    GROUP BY e.facility_id
)
SELECT
    f.facility_name,
    ROUND(x.experience_score, 1) AS experience_score,
    ROUND(r.readmission_rate_pct, 1) AS readmission_rate_pct,
    ROUND(dn.denial_rate_pct, 1) AS denial_rate_pct,
    x.experience_score >= 85 AS passes_experience,
    r.readmission_rate_pct < 8 AS passes_readmission,
    dn.denial_rate_pct < 4 AS passes_denial,
    passes_experience AND passes_readmission AND passes_denial AS beacon_designated
FROM readmission r
JOIN JUNIPER_HEALTH.ANALYTICS.FACILITIES f ON f.facility_id = r.facility_id
JOIN experience x ON x.facility_id = r.facility_id
JOIN denial dn ON dn.facility_id = r.facility_id
ORDER BY beacon_designated DESC, f.facility_name;
