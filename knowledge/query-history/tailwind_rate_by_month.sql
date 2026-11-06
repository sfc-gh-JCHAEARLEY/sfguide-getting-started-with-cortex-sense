-- Project Tailwind: Tailwind Rate by month, with an overall total
-- Owner: Revenue Cycle Operations.
-- Definition: Project_Tailwind.md. In scope: claims for completed, discharged encounters
-- at ACO-participating facilities only. Hit: submitted within 24 hours of discharge.

SELECT
    COALESCE(TO_VARCHAR(DATE_TRUNC('month', e.discharge_date), 'YYYY-MM'), 'All months') AS discharge_month,
    COUNT(*) AS in_scope_claims,
    COUNT_IF(DATEDIFF('hour', e.discharge_date, c.submitted_date) <= 24) AS within_24_hours,
    ROUND(100 * within_24_hours / in_scope_claims, 1) AS tailwind_rate_pct
FROM JUNIPER_HEALTH.ANALYTICS.CLAIMS c
JOIN JUNIPER_HEALTH.ANALYTICS.ENCOUNTERS e ON e.encounter_id = c.encounter_id
JOIN JUNIPER_HEALTH.ANALYTICS.FACILITIES f ON f.facility_id = e.facility_id
WHERE f.is_aco_participant = TRUE
  AND e.status = 'Completed'
  AND e.discharge_date IS NOT NULL
GROUP BY ROLLUP (DATE_TRUNC('month', e.discharge_date))
ORDER BY DATE_TRUNC('month', e.discharge_date) NULLS LAST;
