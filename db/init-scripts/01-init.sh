# !/bin/bash
set -e

# This script is executed during the initialization of the PostgreSQL container.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- -----------------------------------------------------------------------------
    -- 1. Set the database timezone to Africa/Cairo
    -- -----------------------------------------------------------------------------

    ALTER DATABASE "$POSTGRES_DB" SET timezone TO 'Africa/Cairo';

    -- -----------------------------------------------------------------------------
    -- 2. Securely create roles with passwords using DO block to avoid SQL injection
    -- -----------------------------------------------------------------------------

    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'n8n_app_role') THEN
            EXECUTE format('CREATE ROLE n8n_app_role WITH LOGIN PASSWORD %L', '$N8N_DB_PASSWORD');
        END IF;

        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mcp_app_role') THEN
            EXECUTE format('CREATE ROLE mcp_app_role WITH LOGIN PASSWORD %L', '$MCP_DB_PASSWORD');
        END IF;

        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dbmate_app_role') THEN
            EXECUTE format('CREATE ROLE dbmate_app_role WITH LOGIN PASSWORD %L', '$DBMATE_DB_PASSWORD');
        END IF;

        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'backup_app_role') THEN
            EXECUTE format('CREATE ROLE backup_app_role WITH LOGIN PASSWORD %L', '$BACKUP_DB_PASSWORD');
        END IF;
    END \$\$;
    
    -- -----------------------------------------------------------------------------
    -- 3. Manage privileges to the roles
    -- -----------------------------------------------------------------------------

    -- == 3.1 Revoke connect privileges from the roles ==
    REVOKE CONNECT ON DATABASE "$POSTGRES_DB" FROM PUBLIC;

    -- == 3.2Base Access Privileges to the roles ==

    -- == n8n_app_role ==
    GRANT CONNECT ON DATABASE "$POSTGRES_DB" TO n8n_app_role;
    GRANT USAGE, CREATE ON SCHEMA public TO n8n_app_role;

    -- == mcp_app_role ==
    GRANT CONNECT ON DATABASE "$POSTGRES_DB" TO mcp_app_role;
    GRANT USAGE ON SCHEMA public TO mcp_app_role;

    -- == backup_app_role ==
    GRANT CONNECT ON DATABASE "$POSTGRES_DB" TO backup_app_role;
    GRANT USAGE ON SCHEMA public TO backup_app_role;
    ALTER ROLE backup_app_role BYPASSRLS;

    -- == dbmate_app_role ==
    GRANT CONNECT ON DATABASE "$POSTGRES_DB" TO dbmate_app_role;
    GRANT USAGE, CREATE ON SCHEMA public TO dbmate_app_role;
    

    -- == 3.3 Future Object Default Privileges

    -- Tables: Establish read-only baseline for operational and backup roles
    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT SELECT ON TABLES TO n8n_app_role;
    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT SELECT ON TABLES TO mcp_app_role;
    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT SELECT ON TABLES TO backup_app_role;

    -- Sequences: Grant usage for auto-incrementing primary keys on future tables
    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO n8n_app_role;
    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO mcp_app_role;
    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT SELECT ON SEQUENCES TO backup_app_role;


EOSQL