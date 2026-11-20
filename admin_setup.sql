-- =============================================================================
-- Getting Started with Cortex Sense: admin setup
--
-- The part of the setup that needs ACCOUNTADMIN. Run it once, then run setup.sql
-- as JUNIPER_BUILDER. If you don't have ACCOUNTADMIN, send this file to an
-- administrator: they set quickstart_user to your user name and run it for you.
--
-- Creates:
--   roles        JUNIPER_BUILDER (owns the demo, builds the context)
--                JUNIPER_ANALYST (reads the ANALYTICS schema only)
--   warehouse    JUNIPER_WH (XSMALL)
--   integration  JUNIPER_GITHUB (read-only access to this public GitHub repo)
--   database     JUNIPER_HEALTH, owned by JUNIPER_BUILDER
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- The user who will run the quickstart. Running it for yourself? Leave this as is.
-- Running it for someone else? Replace CURRENT_USER() with the name that
-- SELECT CURRENT_USER() returns for them, in single quotes:
--   SET quickstart_user = 'JDOE';
-- If the name contains characters such as @ or ., also wrap it in double quotes
-- and match its case exactly:
--   SET quickstart_user = '"jdoe@company.com"';
SET quickstart_user = CURRENT_USER();

CREATE ROLE IF NOT EXISTS JUNIPER_BUILDER
  COMMENT = 'Owns the Juniper Valley Health demo and builds its Cortex Sense context';
CREATE ROLE IF NOT EXISTS JUNIPER_ANALYST
  COMMENT = 'Juniper Valley Health analyst: reads the ANALYTICS schema only';

-- The Cortex Sense builder role. Only ACCOUNTADMIN can grant it. The grant succeeds
-- even if Cortex Sense isn't enabled on your account; that's checked only when
-- you build the context.
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_SENSE_BUILDER TO ROLE JUNIPER_BUILDER;

-- Scoring an evaluation run on the Cortex Sense Accuracy tab runs as a task owned by
-- the builder role, so it needs EXECUTE TASK on the account.
GRANT EXECUTE TASK ON ACCOUNT TO ROLE JUNIPER_BUILDER;

-- The demo roles go to the quickstart user, and deliberately not to SYSADMIN, so
-- that no other role inherits access to the Cortex Sense context.
GRANT ROLE JUNIPER_BUILDER TO USER IDENTIFIER($quickstart_user);
GRANT ROLE JUNIPER_ANALYST TO USER IDENTIFIER($quickstart_user);

CREATE WAREHOUSE IF NOT EXISTS JUNIPER_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
GRANT USAGE ON WAREHOUSE JUNIPER_WH TO ROLE JUNIPER_BUILDER;
GRANT USAGE ON WAREHOUSE JUNIPER_WH TO ROLE JUNIPER_ANALYST;

CREATE API INTEGRATION IF NOT EXISTS JUNIPER_GITHUB
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-JCHAEARLEY/sfguide-getting-started-with-cortex-sense.git')
  ENABLED = TRUE;
GRANT USAGE ON INTEGRATION JUNIPER_GITHUB TO ROLE JUNIPER_BUILDER;

CREATE DATABASE IF NOT EXISTS JUNIPER_HEALTH;
GRANT OWNERSHIP ON DATABASE JUNIPER_HEALTH TO ROLE JUNIPER_BUILDER COPY CURRENT GRANTS;

SHOW GRANTS TO ROLE JUNIPER_BUILDER;
