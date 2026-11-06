-- =============================================================================
-- Getting Started with Cortex Sense: setup
--
-- Builds the Juniper Valley Health demo: a fictional health system's analytics
-- warehouse, plus the internal docs, saved queries, and dashboard where its business
-- definitions live. Everything is synthetic.
--
-- Run the whole script in a Snowsight SQL worksheet as a user who can use
-- ACCOUNTADMIN. It is safe to re-run.
--
-- Creates:
--   roles        JUNIPER_BUILDER (owns everything, builds the context)
--                JUNIPER_ANALYST (reads the ANALYTICS schema only)
--   warehouse    JUNIPER_WH (XSMALL)
--   integration  JUNIPER_GITHUB (read-only access to this public GitHub repo)
--   database     JUNIPER_HEALTH with schemas SETUP, ANALYTICS, KNOWLEDGE, SENSE
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Step 1: Account-level objects
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS JUNIPER_BUILDER
  COMMENT = 'Owns the Juniper Valley Health demo and builds its Cortex Sense context';
CREATE ROLE IF NOT EXISTS JUNIPER_ANALYST
  COMMENT = 'Juniper Valley Health analyst: reads the ANALYTICS schema only';

-- The Cortex Sense builder role. This statement fails if your account isn't
-- enrolled in the Cortex Sense private preview.
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_SENSE_BUILDER TO ROLE JUNIPER_BUILDER;

-- The demo roles are granted to you, and deliberately not to SYSADMIN, so that no
-- other role inherits access to the Cortex Sense context.
SET my_user = CURRENT_USER();
GRANT ROLE JUNIPER_BUILDER TO USER IDENTIFIER($my_user);
GRANT ROLE JUNIPER_ANALYST TO USER IDENTIFIER($my_user);

CREATE WAREHOUSE IF NOT EXISTS JUNIPER_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
GRANT USAGE ON WAREHOUSE JUNIPER_WH TO ROLE JUNIPER_BUILDER;
GRANT USAGE ON WAREHOUSE JUNIPER_WH TO ROLE JUNIPER_ANALYST;

CREATE API INTEGRATION IF NOT EXISTS JUNIPER_GITHUB
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-JCHAEARLEY/')
  ENABLED = TRUE;
GRANT USAGE ON INTEGRATION JUNIPER_GITHUB TO ROLE JUNIPER_BUILDER;

CREATE DATABASE IF NOT EXISTS JUNIPER_HEALTH;
GRANT OWNERSHIP ON DATABASE JUNIPER_HEALTH TO ROLE JUNIPER_BUILDER COPY CURRENT GRANTS;


-- -----------------------------------------------------------------------------
-- Step 2: Schemas and the Git repository
-- -----------------------------------------------------------------------------
USE ROLE JUNIPER_BUILDER;
USE WAREHOUSE JUNIPER_WH;
USE DATABASE JUNIPER_HEALTH;

CREATE SCHEMA IF NOT EXISTS SETUP
  COMMENT = 'Setup plumbing: the Git repository clone and the CSV load stage';
CREATE SCHEMA IF NOT EXISTS ANALYTICS
  COMMENT = 'Juniper Valley Health analytics warehouse';
CREATE SCHEMA IF NOT EXISTS KNOWLEDGE
  COMMENT = 'Internal docs, saved queries, the operations dashboard, and the certified semantic view';
CREATE SCHEMA IF NOT EXISTS SENSE
  COMMENT = 'Holds only the Cortex Sense context. Do not create or change other objects here.';

CREATE OR REPLACE GIT REPOSITORY SETUP.QUICKSTART_REPO
  API_INTEGRATION = JUNIPER_GITHUB
  ORIGIN = 'https://github.com/sfc-gh-JCHAEARLEY/sfguide-getting-started-with-cortex-sense.git';


-- -----------------------------------------------------------------------------
-- Step 3: The analytics warehouse (ANALYTICS)
-- Comments describe grain and column meaning only. Business definitions live in
-- the KNOWLEDGE schema.
-- -----------------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS SETUP.CSV_STAGE;
COPY FILES INTO @SETUP.CSV_STAGE
  FROM @SETUP.QUICKSTART_REPO/branches/main/data/
  PATTERN = '.*[.]csv';

CREATE OR REPLACE FILE FORMAT SETUP.CSV_FORMAT
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  EMPTY_FIELD_AS_NULL = TRUE;

CREATE OR REPLACE TABLE ANALYTICS.FACILITIES (
  facility_id         NUMBER  COMMENT 'Facility identifier',
  facility_name       VARCHAR COMMENT 'Facility name',
  facility_type       VARCHAR COMMENT 'Hospital, Specialty Hospital, or Clinic',
  city                VARCHAR,
  state               VARCHAR,
  is_aco_participant  BOOLEAN COMMENT 'TRUE when the facility participates in the Juniper Valley Accountable Care Organization'
) COMMENT = 'One row per facility';

CREATE OR REPLACE TABLE ANALYTICS.PATIENTS (
  patient_id  NUMBER  COMMENT 'Patient identifier',
  dob         DATE    COMMENT 'Date of birth',
  sex         VARCHAR COMMENT 'F or M',
  zip_code    VARCHAR
) COMMENT = 'One row per patient';

CREATE OR REPLACE TABLE ANALYTICS.ENCOUNTERS (
  encounter_id    NUMBER        COMMENT 'Encounter identifier',
  patient_id      NUMBER        COMMENT 'References PATIENTS',
  facility_id     NUMBER        COMMENT 'References FACILITIES',
  encounter_type  VARCHAR       COMMENT 'Inpatient, Outpatient, or Emergency',
  admit_date      TIMESTAMP_NTZ COMMENT 'Admission or arrival time',
  discharge_date  TIMESTAMP_NTZ COMMENT 'Discharge time. NULL when the encounter has no discharge',
  status          VARCHAR       COMMENT 'Completed, Cancelled, or In Progress'
) COMMENT = 'One row per patient encounter';

CREATE OR REPLACE TABLE ANALYTICS.DIAGNOSES (
  diagnosis_id    NUMBER  COMMENT 'Diagnosis row identifier',
  encounter_id    NUMBER  COMMENT 'References ENCOUNTERS',
  icd10_code      VARCHAR COMMENT 'ICD-10-CM diagnosis code',
  diagnosis_rank  NUMBER  COMMENT '1 for the principal diagnosis, then secondary diagnoses',
  is_primary      BOOLEAN COMMENT 'TRUE for the principal diagnosis'
) COMMENT = 'One row per coded diagnosis per encounter';

CREATE OR REPLACE TABLE ANALYTICS.CLAIMS (
  claim_id          NUMBER        COMMENT 'Claim identifier',
  encounter_id      NUMBER        COMMENT 'References ENCOUNTERS. One claim per completed encounter',
  payer_name        VARCHAR       COMMENT 'Insurer billed for the claim',
  submitted_date    TIMESTAMP_NTZ COMMENT 'Time the claim was first submitted to the payer',
  billed_amount     NUMBER(12,2)  COMMENT 'Amount billed',
  paid_amount       NUMBER(12,2)  COMMENT 'Amount paid to date',
  claim_status      VARCHAR       COMMENT 'Paid, Partially Paid, Pending, or Denied',
  submission_count  NUMBER        COMMENT 'Number of times the claim was submitted to the payer'
) COMMENT = 'One row per insurance claim';

CREATE OR REPLACE TABLE ANALYTICS.DENIALS (
  denial_id      NUMBER  COMMENT 'Denial row identifier',
  claim_id       NUMBER  COMMENT 'References CLAIMS',
  line_number    NUMBER  COMMENT 'Claim line the denial applies to',
  carc_code      VARCHAR COMMENT 'Claim Adjustment Reason Code',
  denial_reason  VARCHAR,
  denial_date    DATE,
  appeal_status  VARCHAR COMMENT 'Overturned, Upheld, or Not Appealed'
) COMMENT = 'Payer denials at claim line grain. A claim can have several rows';

CREATE OR REPLACE TABLE ANALYTICS.READMISSIONS (
  readmission_id        NUMBER  COMMENT 'Readmission event identifier',
  index_encounter_id    NUMBER  COMMENT 'The earlier inpatient encounter. References ENCOUNTERS',
  readmit_encounter_id  NUMBER  COMMENT 'The later encounter. References ENCOUNTERS',
  days_to_readmit       NUMBER  COMMENT 'Days from index discharge to readmission',
  is_planned            BOOLEAN COMMENT 'TRUE when the readmission was scheduled in advance'
) COMMENT = 'One row per readmission event, recorded against every inpatient index encounter';

CREATE OR REPLACE TABLE ANALYTICS.PATIENT_SURVEYS (
  survey_id       NUMBER COMMENT 'Survey identifier',
  encounter_id    NUMBER COMMENT 'References ENCOUNTERS',
  facility_id     NUMBER COMMENT 'References FACILITIES',
  survey_date     DATE,
  overall_rating  NUMBER COMMENT 'Overall rating on a 1 to 10 scale'
) COMMENT = 'One row per completed patient survey';

COPY INTO ANALYTICS.FACILITIES      FROM @SETUP.CSV_STAGE FILES = ('facilities.csv')      FILE_FORMAT = (FORMAT_NAME = SETUP.CSV_FORMAT);
COPY INTO ANALYTICS.PATIENTS        FROM @SETUP.CSV_STAGE FILES = ('patients.csv')        FILE_FORMAT = (FORMAT_NAME = SETUP.CSV_FORMAT);
COPY INTO ANALYTICS.ENCOUNTERS      FROM @SETUP.CSV_STAGE FILES = ('encounters.csv')      FILE_FORMAT = (FORMAT_NAME = SETUP.CSV_FORMAT);
COPY INTO ANALYTICS.DIAGNOSES       FROM @SETUP.CSV_STAGE FILES = ('diagnoses.csv')       FILE_FORMAT = (FORMAT_NAME = SETUP.CSV_FORMAT);
COPY INTO ANALYTICS.CLAIMS          FROM @SETUP.CSV_STAGE FILES = ('claims.csv')          FILE_FORMAT = (FORMAT_NAME = SETUP.CSV_FORMAT);
COPY INTO ANALYTICS.DENIALS         FROM @SETUP.CSV_STAGE FILES = ('denials.csv')         FILE_FORMAT = (FORMAT_NAME = SETUP.CSV_FORMAT);
COPY INTO ANALYTICS.READMISSIONS    FROM @SETUP.CSV_STAGE FILES = ('readmissions.csv')    FILE_FORMAT = (FORMAT_NAME = SETUP.CSV_FORMAT);
COPY INTO ANALYTICS.PATIENT_SURVEYS FROM @SETUP.CSV_STAGE FILES = ('patient_surveys.csv') FILE_FORMAT = (FORMAT_NAME = SETUP.CSV_FORMAT);

-- The semantic view analysts use today. Its clean_claims metric checks first-pass
-- acceptance only.
CREATE OR REPLACE SEMANTIC VIEW ANALYTICS.CLAIMS_SV
  TABLES (
    claims AS ANALYTICS.CLAIMS PRIMARY KEY (claim_id)
      WITH SYNONYMS ('insurance claims', 'billing claims'),
    denials AS ANALYTICS.DENIALS PRIMARY KEY (denial_id)
      WITH SYNONYMS ('claim denials'),
    encounters AS ANALYTICS.ENCOUNTERS PRIMARY KEY (encounter_id)
      WITH SYNONYMS ('visits', 'admissions'),
    facilities AS ANALYTICS.FACILITIES PRIMARY KEY (facility_id)
      WITH SYNONYMS ('hospitals', 'clinics', 'sites')
  )
  RELATIONSHIPS (
    denials_to_claims AS denials (claim_id) REFERENCES claims,
    claims_to_encounters AS claims (encounter_id) REFERENCES encounters,
    encounters_to_facilities AS encounters (facility_id) REFERENCES facilities
  )
  DIMENSIONS (
    claims.payer_name AS payer_name WITH SYNONYMS ('payer', 'insurer', 'health plan'),
    claims.claim_status AS claim_status,
    facilities.facility_name AS facility_name,
    facilities.is_aco_participant AS is_aco_participant WITH SYNONYMS ('ACO')
  )
  METRICS (
    claims.total_claims AS COUNT(claims.claim_id),
    claims.clean_claims AS COUNT_IF(claims.submission_count = 1)
      WITH SYNONYMS ('clean claim count', 'first pass claims'),
    claims.total_billed AS SUM(claims.billed_amount),
    claims.total_paid AS SUM(claims.paid_amount),
    denials.denied_claims AS COUNT(DISTINCT denials.claim_id)
  )
  COMMENT = 'Claims, denials, encounters, and facilities';


-- -----------------------------------------------------------------------------
-- Step 4: The knowledge corpus (KNOWLEDGE)
-- This is where Juniper Valley Health's definitions live: internal docs, saved
-- queries, the operations dashboard, and the certified semantic view.
-- -----------------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS KNOWLEDGE.KNOWLEDGE_STAGE
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT = 'Internal docs (markdown/) and saved queries (query-history/)';
COPY FILES INTO @KNOWLEDGE.KNOWLEDGE_STAGE/markdown/
  FROM @SETUP.QUICKSTART_REPO/branches/main/knowledge/docs/
  PATTERN = '.*[.]md';
COPY FILES INTO @KNOWLEDGE.KNOWLEDGE_STAGE/query-history/
  FROM @SETUP.QUICKSTART_REPO/branches/main/knowledge/query-history/
  PATTERN = '.*[.]sql';
ALTER STAGE KNOWLEDGE.KNOWLEDGE_STAGE REFRESH;

CREATE STAGE IF NOT EXISTS KNOWLEDGE.STREAMLIT_STAGE
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT = 'Source for the operations dashboard';
COPY FILES INTO @KNOWLEDGE.STREAMLIT_STAGE
  FROM @SETUP.QUICKSTART_REPO/branches/main/streamlit/
  PATTERN = '.*[.]py';
ALTER STAGE KNOWLEDGE.STREAMLIT_STAGE REFRESH;

CREATE OR REPLACE STREAMLIT KNOWLEDGE.OPERATIONS_DASHBOARD
  FROM '@JUNIPER_HEALTH.KNOWLEDGE.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = JUNIPER_WH
  TITLE = 'Juniper Valley Health operations';
ALTER STREAMLIT KNOWLEDGE.OPERATIONS_DASHBOARD ADD LIVE VERSION FROM LAST;

-- Support view for the certified semantic view: metric expressions can't contain
-- subqueries, so the denial flag is resolved here.
CREATE OR REPLACE VIEW KNOWLEDGE.CLAIMS_WITH_DENIAL_FLAG
  COMMENT = 'CLAIMS with has_denial resolved from DENIALS'
AS
SELECT c.*, (d.claim_id IS NOT NULL) AS has_denial
FROM ANALYTICS.CLAIMS c
LEFT JOIN (SELECT DISTINCT claim_id FROM ANALYTICS.DENIALS) d
  ON d.claim_id = c.claim_id;

-- The certified semantic view: clean_claims implements the Metrics Glossary.
CREATE OR REPLACE SEMANTIC VIEW KNOWLEDGE.CLAIMS_SV_CERTIFIED
  TABLES (
    claims AS KNOWLEDGE.CLAIMS_WITH_DENIAL_FLAG PRIMARY KEY (claim_id)
      WITH SYNONYMS ('insurance claims', 'billing claims'),
    denials AS ANALYTICS.DENIALS PRIMARY KEY (denial_id)
      WITH SYNONYMS ('claim denials'),
    encounters AS ANALYTICS.ENCOUNTERS PRIMARY KEY (encounter_id)
      WITH SYNONYMS ('visits', 'admissions'),
    facilities AS ANALYTICS.FACILITIES PRIMARY KEY (facility_id)
      WITH SYNONYMS ('hospitals', 'clinics', 'sites')
  )
  RELATIONSHIPS (
    denials_to_claims AS denials (claim_id) REFERENCES claims,
    claims_to_encounters AS claims (encounter_id) REFERENCES encounters,
    encounters_to_facilities AS encounters (facility_id) REFERENCES facilities
  )
  DIMENSIONS (
    claims.payer_name AS payer_name WITH SYNONYMS ('payer', 'insurer', 'health plan'),
    claims.claim_status AS claim_status,
    claims.has_denial AS has_denial,
    facilities.facility_name AS facility_name,
    facilities.is_aco_participant AS is_aco_participant WITH SYNONYMS ('ACO')
  )
  METRICS (
    claims.total_claims AS COUNT(claims.claim_id),
    claims.clean_claims AS COUNT_IF(claims.submission_count = 1
                                    AND claims.claim_status = 'Paid'
                                    AND claims.has_denial = FALSE)
      WITH SYNONYMS ('clean claim count')
      COMMENT = 'Metrics Glossary definition: first submission, Paid, and never denied',
    claims.total_billed AS SUM(claims.billed_amount),
    claims.total_paid AS SUM(claims.paid_amount),
    denials.denied_claims AS COUNT(DISTINCT denials.claim_id)
  )
  COMMENT = 'Certified claims model. clean_claims follows the Metrics Glossary';

-- Run the saved queries once, the way the analytics team does, so they appear in
-- query history.
EXECUTE IMMEDIATE FROM @KNOWLEDGE.KNOWLEDGE_STAGE/query-history/clean_claim_rate_by_payer.sql;
EXECUTE IMMEDIATE FROM @KNOWLEDGE.KNOWLEDGE_STAGE/query-history/readmission_rate_by_facility.sql;
EXECUTE IMMEDIATE FROM @KNOWLEDGE.KNOWLEDGE_STAGE/query-history/beacon_scorecard.sql;
EXECUTE IMMEDIATE FROM @KNOWLEDGE.KNOWLEDGE_STAGE/query-history/tailwind_rate_by_month.sql;


-- -----------------------------------------------------------------------------
-- Step 5: Analyst access
-- JUNIPER_ANALYST can read ANALYTICS, including the semantic view analysts use
-- today, but nothing in KNOWLEDGE.
-- -----------------------------------------------------------------------------
GRANT USAGE ON DATABASE JUNIPER_HEALTH TO ROLE JUNIPER_ANALYST;
GRANT USAGE ON SCHEMA JUNIPER_HEALTH.ANALYTICS TO ROLE JUNIPER_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA JUNIPER_HEALTH.ANALYTICS TO ROLE JUNIPER_ANALYST;
GRANT SELECT ON SEMANTIC VIEW JUNIPER_HEALTH.ANALYTICS.CLAIMS_SV TO ROLE JUNIPER_ANALYST;


-- -----------------------------------------------------------------------------
-- Step 6: Check the load. Every row should say PASS.
-- -----------------------------------------------------------------------------
SELECT check_name, expected, actual, IFF(expected = actual, 'PASS', 'FAIL') AS result
FROM (
            SELECT 'facilities rows'            AS check_name, 12   AS expected, (SELECT COUNT(*) FROM ANALYTICS.FACILITIES) AS actual
  UNION ALL SELECT 'patients rows',              1720, (SELECT COUNT(*) FROM ANALYTICS.PATIENTS)
  UNION ALL SELECT 'encounters rows',            3174, (SELECT COUNT(*) FROM ANALYTICS.ENCOUNTERS)
  UNION ALL SELECT 'diagnoses rows',             6074, (SELECT COUNT(*) FROM ANALYTICS.DIAGNOSES)
  UNION ALL SELECT 'claims rows',                3131, (SELECT COUNT(*) FROM ANALYTICS.CLAIMS)
  UNION ALL SELECT 'denials rows',               679,  (SELECT COUNT(*) FROM ANALYTICS.DENIALS)
  UNION ALL SELECT 'readmissions rows',          215,  (SELECT COUNT(*) FROM ANALYTICS.READMISSIONS)
  UNION ALL SELECT 'patient_surveys rows',       1131, (SELECT COUNT(*) FROM ANALYTICS.PATIENT_SURVEYS)
  UNION ALL SELECT 'knowledge docs on stage',    4,    (SELECT COUNT(*) FROM DIRECTORY(@KNOWLEDGE.KNOWLEDGE_STAGE) WHERE relative_path LIKE 'markdown/%')
  UNION ALL SELECT 'saved queries on stage',     4,    (SELECT COUNT(*) FROM DIRECTORY(@KNOWLEDGE.KNOWLEDGE_STAGE) WHERE relative_path LIKE 'query-history/%')
  UNION ALL SELECT 'dashboard source on stage',  1,    (SELECT COUNT(*) FROM DIRECTORY(@KNOWLEDGE.STREAMLIT_STAGE))
)
ORDER BY check_name;
