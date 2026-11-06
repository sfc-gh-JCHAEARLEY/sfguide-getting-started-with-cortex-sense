-- =============================================================================
-- Getting Started with Cortex Sense: teardown
--
-- Before running this, delete the Cortex Sense context. In CoCo, ask:
--   Delete the juniper_health Cortex Sense context in JUNIPER_HEALTH.SENSE.
--
-- Then run this whole script in a Snowsight SQL worksheet.
-- =============================================================================

-- JUNIPER_BUILDER owns the database, so it drops it.
USE ROLE JUNIPER_BUILDER;
DROP DATABASE IF EXISTS JUNIPER_HEALTH;

USE ROLE ACCOUNTADMIN;
DROP WAREHOUSE IF EXISTS JUNIPER_WH;
DROP API INTEGRATION IF EXISTS JUNIPER_GITHUB;
DROP ROLE IF EXISTS JUNIPER_ANALYST;
DROP ROLE IF EXISTS JUNIPER_BUILDER;
