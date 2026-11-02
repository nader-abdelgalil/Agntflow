-- migrate:up
ALTER TABLE public.leads
ADD COLUMN IF NOT EXISTS user_name VARCHAR(255);

-- migrate:down

