-- migrate:up
-- =============================================================================
-- Database Schema Definition and Initialization
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. CREATE ENUM TYPES
-- -----------------------------------------------------------------------------
CREATE TYPE lead_status_enum AS ENUM (
    'BOT_ACTIVE',
    'NEW', 
    'TEMPLATE_SENT', 
    'IN_CONVERSATION', 
    'QUALIFIED', 
    'HUMAN_HANDOFF', 
    'DISQUALIFIED',
    'ORDER_PLACED'
);

CREATE TYPE order_status_enum AS ENUM (
    'PENDING',
    'CONFIRMED',
    'PROCESSING',
    'DELIVERED',
    'CANCELLED'
);

CREATE TYPE log_sender_enum AS ENUM (
    'USER',
    'BOT',
    'AGENT'
);

-- -----------------------------------------------------------------------------
-- 2. CREATE 3NF Schema
-- -----------------------------------------------------------------------------
-- == 2.1 Leads Table ===
CREATE TABLE leads (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    phone VARCHAR(20) NOT NULL UNIQUE,
    full_name VARCHAR(255),
    secondary_phone VARCHAR(20),
    email VARCHAR(255),
    platform VARCHAR(50) DEFAULT 'WhatsApp',
    lead_status lead_status_enum DEFAULT 'BOT_ACTIVE',
    delivery_address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- === 2.2 Products Table ===
CREATE TABLE products (
    product_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    description TEXT,
    category VARCHAR(100) DEFAULT 'General',
    stock_quantity INT DEFAULT 0 CHECK (stock_quantity >= 0),
    is_available BOOLEAN DEFAULT TRUE,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- === 2.3 Lead Interests Table ===
CREATE TABLE lead_interests (
    lead_id BIGINT NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (lead_id, product_id)
);

-- === 2.4 Orders Table ===
CREATE TABLE orders (
    order_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lead_id BIGINT NOT NULL REFERENCES leads(id) ON DELETE RESTRICT,
    status order_status_enum DEFAULT 'PENDING',
    total_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (total_amount >= 0),
    shipping_address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- === 2.5 Order Items Table ===
CREATE TABLE order_items (
    order_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- === 2.6 Conversation Logs Table ===
CREATE TABLE conversation_logs (
    log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lead_id BIGINT NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    sender log_sender_enum NOT NULL,
    message_content TEXT NOT NULL,
    intent_detected VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 3. Indexes for Performance Optimization
-- -----------------------------------------------------------------------------
CREATE INDEX idx_leads_phone ON leads(phone);
CREATE INDEX idx_leads_status ON leads(lead_status);
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_products_category ON products(category) WHERE is_available = TRUE;
CREATE INDEX idx_orders_lead_id ON orders(lead_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_conversation_logs_lead ON conversation_logs(lead_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- 4. Trigger to Automatically Update the updated_at Column
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = NOW();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_leads_updated_at BEFORE UPDATE ON leads FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_lead_interests_updated_at BEFORE UPDATE ON lead_interests FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_order_items_updated_at BEFORE UPDATE ON order_items FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
CREATE TRIGGER update_conversation_logs_updated_at BEFORE UPDATE ON conversation_logs FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- =============================================================================
-- Hardened Security, PoLP Grants, and RLS Policies
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Table-Level Permissions (PoLP)
-- -----------------------------------------------------------------------------

-- === n8n_app_role ===
GRANT SELECT ON public.products TO n8n_app_role;
GRANT SELECT, INSERT, UPDATE ON public.leads TO n8n_app_role;
GRANT SELECT, INSERT, UPDATE ON public.orders TO n8n_app_role;
GRANT SELECT, INSERT, UPDATE ON public.order_items TO n8n_app_role;
GRANT SELECT, INSERT, UPDATE ON public.lead_interests TO n8n_app_role;
GRANT SELECT, INSERT, UPDATE ON public.conversation_logs TO n8n_app_role;

-- === mcp_app_role ===
GRANT SELECT ON public.products TO mcp_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.leads TO mcp_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.orders TO mcp_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.conversation_logs TO mcp_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.order_items TO mcp_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lead_interests TO mcp_app_role;

-- -----------------------------------------------------------------------------
-- 2. Enable Row Level Security (RLS)
-- -----------------------------------------------------------------------------
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_interests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_logs ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 3. Row Level Security Policies (RLS Policies)
-- -----------------------------------------------------------------------------

-- === 3.1 n8n_app_role Policies ===
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

-- === 3.2 mcp_app_role Policies ===
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

DROP POLICY IF EXISTS mcp_order_items_policy ON public.order_items;
CREATE POLICY mcp_order_items_policy ON public.order_items
    FOR ALL
    TO mcp_app_role
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS mcp_lead_interests_policy ON public.lead_interests;
CREATE POLICY mcp_lead_interests_policy ON public.lead_interests
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

-- migrate:down

