-- DB schema
-- 1. ضبط المنطقة الزمنية لقاعدة البيانات إلى توقيت مصر
ALTER DATABASE leads_db SET timezone TO 'Africa/Cairo';

-- 2. تنظيف الجداول والدوال القديمة
DROP TABLE IF EXISTS leads CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TYPE IF EXISTS lead_status_enum CASCADE;
DROP FUNCTION IF EXISTS update_updated_at_column CASCADE;

-- 3. إنشاء Enum الحالات
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

-- 4. جدول العملاء (Leads Table)
CREATE TABLE leads (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    phone VARCHAR(20) NOT NULL UNIQUE,
    full_name VARCHAR(255),
    secondary_phone VARCHAR(20),
    email VARCHAR(255),
    platform VARCHAR(50) DEFAULT 'WhatsApp',
    interested_product TEXT,
    ordered_product TEXT,
    delivery_address TEXT,
    lead_status lead_status_enum DEFAULT 'BOT_ACTIVE',
    conversation_summary TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. جدول المنتجات (Products Table)
CREATE TABLE products (
    product_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku VARCHAR(50) UNIQUE,
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

-- 6. إنشاء الفهارس
CREATE INDEX idx_leads_phone ON leads(phone);
CREATE INDEX idx_leads_status ON leads(lead_status);
CREATE INDEX idx_products_category ON products(category) WHERE is_available = TRUE;
CREATE INDEX idx_products_sku ON products(sku);

-- 7. إنشاء دالة الـ Trigger لتحديث updated_at تلقائياً
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = NOW();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 8. ربط الـ Trigger بالجداول
CREATE TRIGGER update_leads_updated_at 
BEFORE UPDATE ON leads 
FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

CREATE TRIGGER update_products_updated_at 
BEFORE UPDATE ON products 
FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
