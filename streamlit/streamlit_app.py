"""Juniper Valley Health operations dashboard.

Used by the revenue cycle and quality teams. Every metric follows the definitions in the
Metrics Glossary, the BEACON designation, and Project Tailwind.
"""

import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()
DB = "JUNIPER_HEALTH.ANALYTICS"

st.set_page_config(page_title="Juniper Valley Health", layout="wide")
st.title("Juniper Valley Health: Revenue Cycle and Quality")


@st.cache_data(ttl=600)
def run(sql: str):
    return session.sql(sql).to_pandas()


ELIGIBLE_CTE = f"""
obstetric AS (
    SELECT DISTINCT encounter_id FROM {DB}.DIAGNOSES WHERE icd10_code LIKE 'O%'
),
eligible AS (
    -- House 30-day readmission denominator: completed adult, non-obstetric inpatient stays
    SELECT e.encounter_id, e.facility_id
    FROM {DB}.ENCOUNTERS e
    JOIN {DB}.PATIENTS p ON p.patient_id = e.patient_id
    WHERE e.encounter_type = 'Inpatient'
      AND e.status <> 'Cancelled'
      AND e.discharge_date IS NOT NULL
      AND DATEDIFF('year', p.dob, e.admit_date) >= 18
      AND e.encounter_id NOT IN (SELECT encounter_id FROM obstetric)
),
qualifying AS (
    -- Numerator: unplanned, within 30 days, and the index admission must be eligible
    SELECT r.readmission_id, r.index_encounter_id
    FROM {DB}.READMISSIONS r
    JOIN eligible el ON el.encounter_id = r.index_encounter_id
    WHERE r.is_planned = FALSE AND r.days_to_readmit <= 30
)
"""

revenue, quality, beacon, tailwind = st.tabs(
    ["Revenue cycle", "Readmissions", "BEACON scorecard", "Project Tailwind"]
)

with revenue:
    st.subheader("Clean Claim Rate by payer")
    st.caption("Clean = first submission AND Paid AND no denial on any line.")
    df = run(f"""
        WITH denied AS (SELECT DISTINCT claim_id FROM {DB}.DENIALS)
        SELECT c.payer_name AS payer,
               COUNT(*) AS claims,
               ROUND(100 * COUNT_IF(c.submission_count = 1 AND c.claim_status = 'Paid'
                                    AND d.claim_id IS NULL) / COUNT(*), 1) AS clean_claim_rate
        FROM {DB}.CLAIMS c
        LEFT JOIN denied d ON d.claim_id = c.claim_id
        GROUP BY c.payer_name
        ORDER BY clean_claim_rate DESC
    """)
    st.bar_chart(df, x="PAYER", y="CLEAN_CLAIM_RATE")
    st.dataframe(df, hide_index=True)

    st.subheader("Denial Rate")
    st.caption("Distinct denied claims over all claims. DENIALS is line-level, so count distinct claim_id.")
    st.dataframe(run(f"""
        SELECT COUNT(DISTINCT d.claim_id) AS denied_claims,
               COUNT(DISTINCT c.claim_id) AS total_claims,
               ROUND(100 * denied_claims / total_claims, 1) AS denial_rate
        FROM {DB}.CLAIMS c
        LEFT JOIN {DB}.DENIALS d ON d.claim_id = c.claim_id
    """), hide_index=True)

with quality:
    st.subheader("30-Day Readmission Rate")
    st.caption("Excludes patients under 18 and obstetric admissions. Planned readmissions never count.")
    df = run(f"""
        WITH {ELIGIBLE_CTE}
        SELECT COALESCE(f.facility_name, 'All facilities') AS facility,
               COUNT(DISTINCT el.encounter_id) AS eligible_index_admissions,
               COUNT(q.readmission_id) AS readmissions,
               ROUND(100 * readmissions / eligible_index_admissions, 1) AS readmission_rate
        FROM eligible el
        JOIN {DB}.FACILITIES f ON f.facility_id = el.facility_id
        LEFT JOIN qualifying q ON q.index_encounter_id = el.encounter_id
        GROUP BY ROLLUP (f.facility_name)
        ORDER BY f.facility_name NULLS LAST
    """)
    st.dataframe(df, hide_index=True)
    st.caption("CMS penalty threshold: above 18%.")

with beacon:
    st.subheader("BEACON designation")
    st.caption("All three required: Experience Score >= 85, readmission < 8%, denial rate < 4%.")
    df = run(f"""
        WITH {ELIGIBLE_CTE},
        readm AS (
            SELECT el.facility_id,
                   100 * COUNT(q.readmission_id) / COUNT(DISTINCT el.encounter_id) AS readmission_rate
            FROM eligible el
            LEFT JOIN qualifying q ON q.index_encounter_id = el.encounter_id
            GROUP BY el.facility_id
        ),
        exp AS (
            SELECT facility_id, 10 * AVG(overall_rating) AS experience_score
            FROM {DB}.PATIENT_SURVEYS GROUP BY facility_id
        ),
        den AS (
            SELECT e.facility_id,
                   100 * COUNT(DISTINCT d.claim_id) / COUNT(DISTINCT c.claim_id) AS denial_rate
            FROM {DB}.CLAIMS c
            JOIN {DB}.ENCOUNTERS e ON e.encounter_id = c.encounter_id
            LEFT JOIN {DB}.DENIALS d ON d.claim_id = c.claim_id
            GROUP BY e.facility_id
        )
        SELECT f.facility_name AS facility,
               ROUND(exp.experience_score, 1) AS experience_score,
               ROUND(readm.readmission_rate, 1) AS readmission_rate,
               ROUND(den.denial_rate, 1) AS denial_rate,
               exp.experience_score >= 85 AND readm.readmission_rate < 8
                   AND den.denial_rate < 4 AS beacon
        FROM readm
        JOIN {DB}.FACILITIES f ON f.facility_id = readm.facility_id
        JOIN exp ON exp.facility_id = readm.facility_id
        JOIN den ON den.facility_id = readm.facility_id
        ORDER BY beacon DESC, facility
    """)
    st.dataframe(df, hide_index=True)

with tailwind:
    st.subheader("Tailwind Rate")
    st.caption("ACO facilities only. Completed, discharged encounters. Submitted within 24 hours of discharge.")
    df = run(f"""
        SELECT DATE_TRUNC('month', e.discharge_date) AS month,
               ROUND(100 * COUNT_IF(DATEDIFF('hour', e.discharge_date, c.submitted_date) <= 24)
                     / COUNT(*), 1) AS tailwind_rate
        FROM {DB}.CLAIMS c
        JOIN {DB}.ENCOUNTERS e ON e.encounter_id = c.encounter_id
        JOIN {DB}.FACILITIES f ON f.facility_id = e.facility_id
        WHERE f.is_aco_participant = TRUE
          AND e.status = 'Completed'
          AND e.discharge_date IS NOT NULL
        GROUP BY month
        ORDER BY month
    """)
    st.line_chart(df, x="MONTH", y="TAILWIND_RATE")
    st.caption("Target 80%, stretch 90%.")
