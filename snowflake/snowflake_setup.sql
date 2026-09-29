-- =====================================================================
-- Last.fm pipeline: Snowflake setup (one-time setup)
-- Run this once in a Snowsight SQL worksheet, top to bottom ("Run All").
-- Safe to re-run: every statement uses IF NOT EXISTS or is a GRANT.
-- =====================================================================


-- ---------------------------------------------------------------------
-- PART A: Objects (warehouse, database, schemas, table, stage)
-- SYSADMIN is the role meant for creating objects.
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;

-- Smallest warehouse, turns itself off after 60 s idle so it costs almost nothing
CREATE WAREHOUSE IF NOT EXISTS LASTFM_WH
  WAREHOUSE_SIZE      = 'XSMALL'
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Compute for the Last.fm pipeline (GitHub Actions)';

CREATE DATABASE IF NOT EXISTS LASTFM;

CREATE SCHEMA IF NOT EXISTS LASTFM.RAW;      -- raw JSON lands here
CREATE SCHEMA IF NOT EXISTS LASTFM.STAGING;  -- dbt views (stg_top_tracks)
CREATE SCHEMA IF NOT EXISTS LASTFM.MARTS;    -- dbt tables (fct_chart_drops)

-- Same structure as the old account, so the dbt source still matches
CREATE TABLE IF NOT EXISTS LASTFM.RAW.TOP_TRACKS (
  RAW_DATA  VARIANT,
  LOADED_AT TIMESTAMP_NTZ
);

-- Tells Snowflake the staged files are JSON
CREATE FILE FORMAT IF NOT EXISTS LASTFM.RAW.JSON_FORMAT
  TYPE = JSON;

-- Internal stage: replaces the old Azure stage. Files are PUT here, then COPY INTO.
CREATE STAGE IF NOT EXISTS LASTFM.RAW.LASTFM_STAGE
  FILE_FORMAT = LASTFM.RAW.JSON_FORMAT
  COMMENT = 'Internal stage for lastfm_top_tracks_YYYY-MM-DDTHH-MI.json files';


-- ---------------------------------------------------------------------
-- PART B: Role, permissions and service user
-- SECURITYADMIN is the role meant for users, roles and grants.
-- ---------------------------------------------------------------------
USE ROLE SECURITYADMIN;

-- One role that holds exactly what the pipeline needs, nothing more
CREATE ROLE IF NOT EXISTS LASTFM_PIPELINE_ROLE
  COMMENT = 'Used by GitHub Actions: load raw data and run dbt';

-- Let SYSADMIN (and therefore you) see and manage whatever this role creates
GRANT ROLE LASTFM_PIPELINE_ROLE TO ROLE SYSADMIN;

-- Warehouse: use it and start/stop it
GRANT USAGE, OPERATE ON WAREHOUSE LASTFM_WH TO ROLE LASTFM_PIPELINE_ROLE;

-- Database
GRANT USAGE         ON DATABASE LASTFM TO ROLE LASTFM_PIPELINE_ROLE;
GRANT CREATE SCHEMA ON DATABASE LASTFM TO ROLE LASTFM_PIPELINE_ROLE;  -- in case dbt wants its own schema names

-- RAW: load step (PUT + COPY INTO) and dbt reading the source
GRANT USAGE          ON SCHEMA      LASTFM.RAW              TO ROLE LASTFM_PIPELINE_ROLE;
GRANT SELECT, INSERT ON TABLE       LASTFM.RAW.TOP_TRACKS   TO ROLE LASTFM_PIPELINE_ROLE;
GRANT READ, WRITE    ON STAGE       LASTFM.RAW.LASTFM_STAGE TO ROLE LASTFM_PIPELINE_ROLE;
GRANT USAGE          ON FILE FORMAT LASTFM.RAW.JSON_FORMAT  TO ROLE LASTFM_PIPELINE_ROLE;

-- STAGING and MARTS: dbt builds views and tables here
GRANT USAGE, CREATE VIEW, CREATE TABLE ON SCHEMA LASTFM.STAGING TO ROLE LASTFM_PIPELINE_ROLE;
GRANT USAGE, CREATE VIEW, CREATE TABLE ON SCHEMA LASTFM.MARTS   TO ROLE LASTFM_PIPELINE_ROLE;

-- Service user: TYPE = SERVICE means no password and no browser login.
-- It will log in with an RSA key only; we attach the public key in step 2.
CREATE USER IF NOT EXISTS LASTFM_PIPELINE_USER
  TYPE              = SERVICE
  DEFAULT_ROLE      = LASTFM_PIPELINE_ROLE
  DEFAULT_WAREHOUSE = LASTFM_WH
  DEFAULT_NAMESPACE = LASTFM.RAW
  COMMENT = 'GitHub Actions service user for the Last.fm pipeline';

GRANT ROLE LASTFM_PIPELINE_ROLE TO USER LASTFM_PIPELINE_USER;


-- ---------------------------------------------------------------------
-- PART C: Check that everything is there
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;

SHOW SCHEMAS IN DATABASE LASTFM;          -- expect RAW, STAGING, MARTS (+ INFORMATION_SCHEMA, PUBLIC)
SHOW TABLES  IN SCHEMA LASTFM.RAW;        -- expect TOP_TRACKS
SHOW STAGES  IN SCHEMA LASTFM.RAW;        -- expect LASTFM_STAGE

USE ROLE SECURITYADMIN;
SHOW GRANTS TO ROLE LASTFM_PIPELINE_ROLE; -- the list of permissions above
DESC USER LASTFM_PIPELINE_USER;           -- TYPE = SERVICE; then attach the public key (see README)
