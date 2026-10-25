-- migrate:up
CREATE TABLE public.messages (
    message_id TEXT PRIMARY KEY,
    lead_id BIGINT NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    message_type TEXT NOT NULL,
    content TEXT NOT NULL,
    media_id TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_media_id ON public.messages(media_id);
CREATE TRIGGER update_messages_updated_at BEFORE UPDATE ON public.messages FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- migrate:down

