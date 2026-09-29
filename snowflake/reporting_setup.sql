-- =====================================================================
-- Last.fm pipeline: read-only access for the Data Studio dashboard
-- Run once in a Snowsight worksheet with "Run All" (after snowflake_setup.sql).
-- Safe to re-run.
-- =====================================================================

USE ROLE SECURITYADMIN;

-- A role that can only READ the modelled data (STAGING + MARTS), never RAW, never write
CREATE ROLE IF NOT EXISTS LASTFM_REPORTING_ROLE
  COMMENT = 'Read-only role for the Data Studio dashboard';

GRANT ROLE LASTFM_REPORTING_ROLE TO ROLE SYSADMIN;

-- Compute to run the dashboard queries (same small warehouse, auto-suspends after 60 s)
GRANT USAGE ON WAREHOUSE LASTFM_WH TO ROLE LASTFM_REPORTING_ROLE;

GRANT USAGE ON DATABASE LASTFM                 TO ROLE LASTFM_REPORTING_ROLE;
GRANT USAGE ON SCHEMA   LASTFM.STAGING         TO ROLE LASTFM_REPORTING_ROLE;
GRANT USAGE ON SCHEMA   LASTFM.MARTS           TO ROLE LASTFM_REPORTING_ROLE;

-- What exists today
GRANT SELECT ON ALL VIEWS  IN SCHEMA LASTFM.STAGING TO ROLE LASTFM_REPORTING_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA LASTFM.MARTS   TO ROLE LASTFM_REPORTING_ROLE;

-- IMPORTANT: dbt rebuilds fct_chart_drops every day (CREATE OR REPLACE), which
-- removes grants on the old table. FUTURE grants give the permission automatically
-- to every new version of the table/view, so the dashboard keeps working.
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA LASTFM.STAGING TO ROLE LASTFM_REPORTING_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA LASTFM.MARTS   TO ROLE LASTFM_REPORTING_ROLE;

-- Service user for Data Studio: no password, logs in with its own RSA key
CREATE USER IF NOT EXISTS LASTFM_REPORTING_USER
  TYPE              = SERVICE
  DEFAULT_ROLE      = LASTFM_REPORTING_ROLE
  DEFAULT_WAREHOUSE = LASTFM_WH
  DEFAULT_NAMESPACE = LASTFM.MARTS
  COMMENT = 'Data Studio dashboard, read-only';

GRANT ROLE LASTFM_REPORTING_ROLE TO USER LASTFM_REPORTING_USER;

-- Check
SHOW GRANTS TO ROLE LASTFM_REPORTING_ROLE;
SHOW FUTURE GRANTS IN SCHEMA LASTFM.MARTS;
DESC USER LASTFM_REPORTING_USER;   -- TYPE = SERVICE; attach the public key next
