-- =====================================================================
-- Last.fm pipeline: read-only Snowflake MCP server for the Claude dashboard
-- Run once in a Snowsight worksheet with "Run All" (after reporting_setup.sql).
-- Safe to re-run. Replace <YOUR_SNOWFLAKE_USER> before running.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PART A: MCP server with a single SQL tool
-- Lives next to the data it serves. The tool runs SQL with the caller's
-- role, so what a reader can see is still decided by grants, not by the server.
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;

CREATE MCP SERVER IF NOT EXISTS LASTFM.MARTS.LASTFM_MCP
  FROM SPECIFICATION $$
    tools:
      - name: "lastfm_sql"
        type: "SYSTEM_EXECUTE_SQL"
        title: "Last.fm SQL"
        description: "Read-only SQL over LASTFM.STAGING and LASTFM.MARTS (Last.fm global Top 50 history and chart drops)."
  $$;

-- Only the read-only reporting role may call it
GRANT USAGE ON MCP SERVER LASTFM.MARTS.LASTFM_MCP TO ROLE LASTFM_REPORTING_ROLE;


-- ---------------------------------------------------------------------
-- PART B: OAuth, so Claude signs in as you (no keys or passwords in Claude)
-- Public client + PKCE: Claude only needs the client ID, no secret.
-- Recreating the integration issues a NEW client ID: remove the connector in
-- Claude and add it again, or sign-in fails with the old ID.
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;  -- security integrations need ACCOUNTADMIN

CREATE SECURITY INTEGRATION IF NOT EXISTS LASTFM_CLAUDE_OAUTH
  TYPE                         = OAUTH
  OAUTH_CLIENT                 = CUSTOM
  OAUTH_CLIENT_TYPE            = 'PUBLIC'
  OAUTH_REDIRECT_URI           = 'https://claude.ai/api/mcp/auth_callback'
  OAUTH_ENFORCE_PKCE           = TRUE
  OAUTH_ISSUE_REFRESH_TOKENS   = TRUE
  OAUTH_REFRESH_TOKEN_VALIDITY = 7776000          -- 90 days, then sign in again
  ENABLED                      = TRUE
  COMMENT = 'Claude connector for the Last.fm MCP server';

-- Client ID for Claude's custom connector (Advanced settings; leave the secret empty)
SELECT PARSE_JSON(SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('LASTFM_CLAUDE_OAUTH')):OAUTH_CLIENT_ID::STRING AS client_id;


-- ---------------------------------------------------------------------
-- PART C: Your own login uses the read-only role by default
-- Claude's session takes your default role, so this keeps it away from
-- RAW and from anything that can write.
-- ---------------------------------------------------------------------
USE ROLE SECURITYADMIN;

GRANT ROLE LASTFM_REPORTING_ROLE TO USER <YOUR_SNOWFLAKE_USER>;
ALTER USER <YOUR_SNOWFLAKE_USER> SET
  DEFAULT_ROLE      = LASTFM_REPORTING_ROLE
  DEFAULT_WAREHOUSE = LASTFM_WH;


-- ---------------------------------------------------------------------
-- PART D: Check
-- Server URL for Claude (Settings -> Connectors -> Add custom connector):
--   https://<ORGNAME-ACCOUNTNAME>.snowflakecomputing.com/api/v2/databases/LASTFM/schemas/MARTS/mcp-servers/LASTFM_MCP
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;
SHOW MCP SERVERS IN SCHEMA LASTFM.MARTS;
DESCRIBE MCP SERVER LASTFM.MARTS.LASTFM_MCP;
DESC SECURITY INTEGRATION LASTFM_CLAUDE_OAUTH;
