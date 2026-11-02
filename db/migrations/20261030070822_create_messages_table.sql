-- migrate:up
DROP TABLE IF EXISTS public.messages CASCADE;

CREATE TABLE public.messages (
    message_id TEXT,
    lead_id BIGINT NOT NULL REFERENCES public.leads(id) ON DELETE CASCADE,
    message_type TEXT NOT NULL,
    content TEXT,
    media_id TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (message_id, created_at)
) PARTITION BY RANGE (created_at);

CREATE TABLE public.messages_y2026 PARTITION OF public.messages
    FOR VALUES FROM ('2026-01-01 00:00:00') TO ('2027-01-01 00:00:00');

CREATE INDEX idx_media_id ON public.messages(media_id);
CREATE INDEX idx_messages_lead_created_at ON public.messages (lead_id, created_at DESC);

CREATE TRIGGER update_messages_updated_at 
BEFORE UPDATE ON public.messages 
FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

GRANT SELECT, INSERT, UPDATE ON public.messages TO n8n_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.messages TO mcp_app_role;

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS n8n_messages_policy ON public.messages;
CREATE POLICY n8n_messages_policy ON public.messages
    FOR ALL
    TO n8n_app_role
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS mcp_messages_policy ON public.messages;
CREATE POLICY mcp_messages_policy ON public.messages
    FOR ALL
    TO mcp_app_role
    USING (true)
    WITH CHECK (true);

-- migrate:down

