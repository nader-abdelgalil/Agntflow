-- =============================================================================
-- 03-Security.sql: Hardened Security, PoLP Grants, and RLS Policies
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Revoke Default Privileges from PUBLIC
-- -----------------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM n8n_app_role, mcp_app_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM n8n_app_role, mcp_app_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM n8n_app_role, mcp_app_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM n8n_app_role, mcp_app_role;

-- -----------------------------------------------------------------------------
-- 2. Table-Level Permissions (PoLP)
-- -----------------------------------------------------------------------------

-- === n8n_app_role ===
GRANT SELECT ON public.products TO n8n_app_role;

GRANT SELECT, INSERT, UPDATE ON public.leads TO n8n_app_role;
GRANT SELECT, INSERT, UPDATE ON public.orders TO n8n_app_role;
GRANT SELECT, INSERT, UPDATE ON public.order_items TO n8n_app_role;
GRANT SELECT, INSERT, UPDATE ON public.lead_interests TO n8n_app_role;
GRANT SELECT, INSERT, UPDATE ON public.conversation_logs TO n8n_app_role;

-- Allow n8n_app_role to use sequences for auto-incrementing IDs
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO n8n_app_role;

-- === mcp_app_role ===
GRANT SELECT ON public.products TO mcp_app_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.leads TO mcp_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.orders TO mcp_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.conversation_logs TO mcp_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.order_items TO mcp_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lead_interests TO mcp_app_role;

-- Allow mcp_app_role to use sequences for auto-incrementing IDs
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mcp_app_role;

-- -----------------------------------------------------------------------------
-- 2. Default Privileges
-- -----------------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO n8n_app_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO mcp_app_role;

-- -----------------------------------------------------------------------------
-- 3. Enable Row Level Security (RLS)
-- -----------------------------------------------------------------------------
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_interests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_logs ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 4. Row Level Security Policies (RLS Policies)
-- -----------------------------------------------------------------------------

-- === 4.1 n8n_app_role Policies ===
DROP POLICY IF EXISTS n8n_leads_policy ON public.leads;
CREATE POLICY n8n_leads_policy ON public.leads
    FOR ALL
    TO n8n_app_role
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS n8n_orders_policy ON public.orders;
CREATE POLICY n8n_orders_policy ON public.orders
    FOR ALL
    TO n8n_app_role
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS n8n_order_items_policy ON public.order_items;
CREATE POLICY n8n_order_items_policy ON public.order_items
    FOR ALL
    TO n8n_app_role
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS n8n_lead_interests_policy ON public.lead_interests;
CREATE POLICY n8n_lead_interests_policy ON public.lead_interests
    FOR ALL
    TO n8n_app_role
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS n8n_conversation_logs_policy ON public.conversation_logs;
CREATE POLICY n8n_conversation_logs_policy ON public.conversation_logs
    FOR ALL
    TO n8n_app_role
    USING (true)
    WITH CHECK (true);

-- === 4.2 mcp_app_role Policies ===
DROP POLICY IF EXISTS mcp_leads_policy ON public.leads;
CREATE POLICY mcp_leads_policy ON public.leads
    FOR ALL
    TO mcp_app_role
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS mcp_orders_policy ON public.orders;
CREATE POLICY mcp_orders_policy ON public.orders
    FOR ALL
    TO mcp_app_role
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS mcp_conversation_logs_policy ON public.conversation_logs;
CREATE POLICY mcp_conversation_logs_policy ON public.conversation_logs
    FOR ALL
    TO mcp_app_role
    USING (true)
    WITH CHECK (true);