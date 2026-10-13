#!/bin/bash
set -e

# This script is executed during the initialization of the PostgreSQL container.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- 1. Set the database timezone to Africa/Cairo
    ALTER DATABASE "$POSTGRES_DB" SET timezone TO 'Africa/Cairo';

    -- 3. Securely create roles with passwords using DO block to avoid SQL injection
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mcp_app_role') THEN
            EXECUTE format('CREATE ROLE mcp_app_role WITH LOGIN PASSWORD %L', '$MCP_DB_PASSWORD');
        END IF;

        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'n8n_app_role') THEN
            EXECUTE format('CREATE ROLE n8n_app_role WITH LOGIN PASSWORD %L', '$N8N_DB_PASSWORD');
        END IF;
    END \$\$;
    
EOSQL