-- =============================================================================
-- Getting Started with Cortex Sense: teardown
--
-- Before running this, delete the Cortex Sense context. In CoCo, ask:
--   Delete the JUNIPER_HEALTH Cortex Sense context in JUNIPER_HEALTH.SENSE.
--
-- Then run this whole script in a Snowsight SQL worksheet. If an administrator ran
-- admin_setup.sql for you, run Part 1 yourself and send them Part 2.
-- =============================================================================

-- Part 1: JUNIPER_BUILDER owns the database, so it drops it.
USE ROLE JUNIPER_BUILDER;
DROP DATABASE IF EXISTS JUNIPER_HEALTH;

-- Part 2: the account-level objects from admin_setup.sql.
USE ROLE ACCOUNTADMIN;
DROP WAREHOUSE IF EXISTS JUNIPER_WH;
DROP API INTEGRATION IF EXISTS JUNIPER_GITHUB;
DROP ROLE IF EXISTS JUNIPER_ANALYST;
DROP ROLE IF EXISTS JUNIPER_BUILDER;
