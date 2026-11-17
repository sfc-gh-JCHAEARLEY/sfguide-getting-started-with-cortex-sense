-- =============================================================================
-- Getting Started with Cortex Sense: answer key
--
-- Computes the correct answer to every question in evals/questions.yaml from the
-- base tables, using the definitions in knowledge/docs. Each query is labeled with
-- the question ids it answers. setup.sql does not run this file.
--
-- Run it only AFTER you've finished comparing answers. Anything you run lands in
-- query history, which Cortex Sense can read the next time the context is built.
-- =============================================================================
USE ROLE JUNIPER_BUILDER;
USE WAREHOUSE JUNIPER_WH;
USE SCHEMA JUNIPER_HEALTH.ANALYTICS;

-- r1: Overall denial rate. Expect 12.1% (379 of 3,131).
SELECT COUNT(DISTINCT d.claim_id) AS denied_claims,
       COUNT(DISTINCT c.claim_id) AS total_claims,
       ROUND(100 * denied_claims / total_claims, 1) AS denial_rate_pct
FROM CLAIMS c
LEFT JOIN DENIALS d ON d.claim_id = c.claim_id;

-- r2: ACO facilities. Expect five.
SELECT facility_name FROM FACILITIES WHERE is_aco_participant ORDER BY facility_id;

-- r3: Share of billed charges paid. Expect 58.4% ($15.93M of $27.26M).
SELECT SUM(billed_amount) AS billed, SUM(paid_amount) AS paid,
       ROUND(100 * paid / billed, 1) AS paid_share_pct
FROM CLAIMS;

-- r4: Claims by payer. Expect Medicare first (798), then UnitedHealthcare (576).
SELECT payer_name, COUNT(*) AS claims FROM CLAIMS GROUP BY payer_name ORDER BY claims DESC;

-- q1: Clean claim rate. Expect 63.9% (2,001 of 3,131), UnitedHealthcare last.
WITH denied AS (SELECT DISTINCT claim_id FROM DENIALS)
SELECT COALESCE(c.payer_name, 'All payers') AS payer,
       COUNT(*) AS total_claims,
       COUNT_IF(c.submission_count = 1 AND c.claim_status = 'Paid' AND d.claim_id IS NULL) AS clean_claims,
       ROUND(100 * clean_claims / total_claims, 1) AS clean_claim_rate_pct,
       ROUND(100 * COUNT_IF(c.submission_count = 1) / total_claims, 1) AS first_pass_only_pct
FROM CLAIMS c
LEFT JOIN denied d ON d.claim_id = c.claim_id
GROUP BY ROLLUP (c.payer_name)
ORDER BY c.payer_name IS NULL DESC, clean_claim_rate_pct DESC;

-- q2: 30-day readmission rate. Expect 10.5% (62 of 590 eligible index admissions).
WITH obstetric AS (
    SELECT DISTINCT encounter_id FROM DIAGNOSES WHERE icd10_code LIKE 'O%'
),
eligible AS (
    SELECT e.encounter_id, e.facility_id
    FROM ENCOUNTERS e
    JOIN PATIENTS p ON p.patient_id = e.patient_id
    WHERE e.encounter_type = 'Inpatient'
      AND e.status <> 'Cancelled'
      AND e.discharge_date IS NOT NULL
      AND DATEDIFF('year', p.dob, e.admit_date) >= 18
      AND e.encounter_id NOT IN (SELECT encounter_id FROM obstetric)
)
SELECT
    (SELECT COUNT(*) FROM READMISSIONS r JOIN eligible el ON el.encounter_id = r.index_encounter_id
      WHERE NOT r.is_planned AND r.days_to_readmit <= 30)                     AS qualifying_readmissions,
    (SELECT COUNT(*) FROM eligible)                                           AS eligible_index_admissions,
    ROUND(100 * qualifying_readmissions / eligible_index_admissions, 1)       AS readmission_rate_pct,
    -- The naive reading: unplanned readmissions over all inpatient encounters.
    ROUND(100 * (SELECT COUNT_IF(NOT is_planned) FROM READMISSIONS)
              / (SELECT COUNT(*) FROM ENCOUNTERS WHERE encounter_type = 'Inpatient'), 1) AS naive_rate_pct;

-- q3, q5, q7, q8, q10, q11, q12: BEACON scorecard and release-policy suppression,
-- one row per facility with inpatient care (clinics have none, so they're absent).
-- Expect only Summit Orthopedic Hospital designated. Cedar Ridge misses only on
-- readmission and Willow Creek only on denial rate. No facility is above 18%; the
-- highest is Granite Falls at 16.7%. Three of the eight reporting facilities have
-- fewer than 20 eligible index admissions.
-- The naive column counts unplanned readmissions within 30 days over all inpatient
-- encounters, with no exclusions. It puts four facilities above 18%.
WITH obstetric AS (
    SELECT DISTINCT encounter_id FROM DIAGNOSES WHERE icd10_code LIKE 'O%'
),
eligible AS (
    SELECT e.encounter_id, e.facility_id
    FROM ENCOUNTERS e
    JOIN PATIENTS p ON p.patient_id = e.patient_id
    WHERE e.encounter_type = 'Inpatient'
      AND e.status <> 'Cancelled'
      AND e.discharge_date IS NOT NULL
      AND DATEDIFF('year', p.dob, e.admit_date) >= 18
      AND e.encounter_id NOT IN (SELECT encounter_id FROM obstetric)
),
naive AS (
    SELECT e.facility_id,
           100 * COUNT(r.readmission_id) / COUNT(DISTINCT e.encounter_id) AS naive_readmission_rate_pct
    FROM ENCOUNTERS e
    LEFT JOIN READMISSIONS r
           ON r.index_encounter_id = e.encounter_id AND NOT r.is_planned AND r.days_to_readmit <= 30
    WHERE e.encounter_type = 'Inpatient'
    GROUP BY e.facility_id
),
readm AS (
    SELECT el.facility_id,
           COUNT(DISTINCT el.encounter_id) AS eligible_index_admissions,
           100 * COUNT(r.readmission_id) / eligible_index_admissions AS readmission_rate_pct
    FROM eligible el
    LEFT JOIN READMISSIONS r
           ON r.index_encounter_id = el.encounter_id AND NOT r.is_planned AND r.days_to_readmit <= 30
    GROUP BY el.facility_id
),
exp AS (
    SELECT facility_id, 10 * AVG(overall_rating) AS experience_score FROM PATIENT_SURVEYS GROUP BY facility_id
),
den AS (
    SELECT e.facility_id, 100 * COUNT(DISTINCT d.claim_id) / COUNT(DISTINCT c.claim_id) AS denial_rate_pct
    FROM CLAIMS c
    JOIN ENCOUNTERS e ON e.encounter_id = c.encounter_id
    LEFT JOIN DENIALS d ON d.claim_id = c.claim_id
    GROUP BY e.facility_id
)
SELECT f.facility_name,
       ROUND(exp.experience_score, 1) AS experience_score,
       ROUND(readm.readmission_rate_pct, 1) AS readmission_rate_pct,
       ROUND(den.denial_rate_pct, 1) AS denial_rate_pct,
       exp.experience_score >= 85 AND readm.readmission_rate_pct < 8 AND den.denial_rate_pct < 4 AS beacon,
       readm.eligible_index_admissions,
       readm.eligible_index_admissions < 20 AS suppressed_in_external_release,
       ROUND(naive.naive_readmission_rate_pct, 1) AS naive_readmission_rate_pct
FROM readm
JOIN FACILITIES f ON f.facility_id = readm.facility_id
JOIN naive ON naive.facility_id = readm.facility_id
JOIN exp ON exp.facility_id = readm.facility_id
JOIN den ON den.facility_id = readm.facility_id
ORDER BY f.facility_id;

-- q4: Tailwind rate. Expect 78.3% (1,175 of 1,500) at ACO facilities, against an 80%
-- target. Across all facilities the same calculation gives 49.7%.
SELECT IFF(GROUPING(f.is_aco_participant) = 1, 'All facilities',
           IFF(f.is_aco_participant, 'ACO facilities (in scope)', 'Non-ACO facilities')) AS scope,
       COUNT(*) AS claims,
       COUNT_IF(DATEDIFF('hour', e.discharge_date, c.submitted_date) <= 24) AS within_24_hours,
       ROUND(100 * within_24_hours / claims, 1) AS rate_pct
FROM CLAIMS c
JOIN ENCOUNTERS e ON e.encounter_id = c.encounter_id
JOIN FACILITIES f ON f.facility_id = e.facility_id
WHERE e.status = 'Completed' AND e.discharge_date IS NOT NULL
GROUP BY ROLLUP (f.is_aco_participant)
ORDER BY GROUPING(f.is_aco_participant), f.is_aco_participant DESC;

-- q6: Experience Score for every facility. Expect 83.6 system-wide, Summit Orthopedic
-- Hospital highest at 91.9 and Sagebrush Regional Hospital lowest at 76.2.
SELECT COALESCE(f.facility_name, 'All facilities') AS facility,
       COUNT(*) AS surveys,
       ROUND(10 * AVG(s.overall_rating), 1) AS experience_score
FROM PATIENT_SURVEYS s
JOIN FACILITIES f ON f.facility_id = s.facility_id
GROUP BY ROLLUP (f.facility_name)
ORDER BY GROUPING(f.facility_name) DESC, experience_score DESC;

-- q9: Tailwind rate by ACO facility. Expect Northgate Family Clinic lowest at 75.0% and
-- Willow Creek Hospital the only facility at the 80% target, at 80.3%.
SELECT f.facility_name,
       COUNT(*) AS claims,
       COUNT_IF(DATEDIFF('hour', e.discharge_date, c.submitted_date) <= 24) AS within_24_hours,
       ROUND(100 * within_24_hours / claims, 1) AS rate_pct
FROM CLAIMS c
JOIN ENCOUNTERS e ON e.encounter_id = c.encounter_id
JOIN FACILITIES f ON f.facility_id = e.facility_id
WHERE f.is_aco_participant AND e.status = 'Completed' AND e.discharge_date IS NOT NULL
GROUP BY f.facility_name
ORDER BY rate_pct;

-- q13 and q14 are policy questions with no calculation. Their answers are in
-- knowledge/docs/External_Data_Release_Policy.md.
