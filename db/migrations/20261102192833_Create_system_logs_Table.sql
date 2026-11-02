-- migrate:up

-------------------------------------------------------------------------------
-- 1. Create system_logs Table
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.system_logs (
    log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workflow_id VARCHAR(255),
    execution_id VARCHAR(255),
    node_name VARCHAR(255) NOT NULL,
    error_code VARCHAR(100),
    error_status VARCHAR(50),
    error_message TEXT NOT NULL,
    error_description TEXT,
    lead_id BIGINT REFERENCES public.leads(id) ON DELETE SET NULL,
    message_id TEXT,
    media_id TEXT,
    error_details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-------------------------------------------------------------------------------
-- 2. Performance Optimization & Indexes
-------------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_system_logs_node_name ON public.system_logs (node_name);
CREATE INDEX IF NOT EXISTS idx_system_logs_lead_id ON public.system_logs (lead_id);
CREATE INDEX IF NOT EXISTS idx_system_logs_media_id ON public.system_logs (media_id);
CREATE INDEX IF NOT EXISTS idx_system_logs_created_at ON public.system_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_system_logs_error_code ON public.system_logs (error_code);

-------------------------------------------------------------------------------
-- 3. Trigger Configuration for updated_at
-------------------------------------------------------------------------------
CREATE TRIGGER update_system_logs_updated_at
    BEFORE UPDATE ON public.system_logs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-------------------------------------------------------------------------------
-- 4. Role Permissions & PoLP Grants
-------------------------------------------------------------------------------
-- Grants for n8n_app_role (Operational Write, No DELETE)
GRANT SELECT, INSERT, UPDATE ON public.system_logs TO n8n_app_role;

-- Grants for mcp_app_role (Full Operational Access)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.system_logs TO mcp_app_role;

-------------------------------------------------------------------------------
-- 5. Row Level Security (RLS) Policies
-------------------------------------------------------------------------------
ALTER TABLE public.system_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY n8n_system_logs_policy ON public.system_logs
    FOR ALL
    TO n8n_app_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY mcp_system_logs_policy ON public.system_logs
    FOR ALL
    TO mcp_app_role
    USING (true)
    WITH CHECK (true);

-- migrate:down

DROP TABLE IF EXISTS public.system_logs;