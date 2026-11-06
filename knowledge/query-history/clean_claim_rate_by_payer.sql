-- Clean Claim Rate by payer
-- Owner: Revenue Cycle Analytics. Used for quarterly payer contract reviews.
-- Definition: Metrics Glossary, Clean Claim Rate. A claim is clean only when it was
-- accepted on first submission, is Paid, and has no row in DENIALS.

WITH denied_claims AS (
    SELECT DISTINCT claim_id
    FROM JUNIPER_HEALTH.ANALYTICS.DENIALS
)
SELECT
    c.payer_name,
    COUNT(*) AS total_claims,
    COUNT_IF(c.submission_count = 1
             AND c.claim_status = 'Paid'
             AND d.claim_id IS NULL) AS clean_claims,
    ROUND(100 * clean_claims / total_claims, 1) AS clean_claim_rate_pct
FROM JUNIPER_HEALTH.ANALYTICS.CLAIMS c
LEFT JOIN denied_claims d ON d.claim_id = c.claim_id
GROUP BY c.payer_name
ORDER BY clean_claim_rate_pct DESC;
