# PostgreSQL Database Architecture & Security Model Specification

## Architecture Metadata & Ownership

- **Architect & Maintainer**: Nader Abdelgalil

- **System Architecture**: Production-Grade Multi-Service PostgreSQL Environment (n8n, MCP Server, dbmate, Backup)

- **Specification Version**: `1.0.0`

- **Initial Deployment Date**: October 2026

## Overview

This document serves as the comprehensive architectural specification for the production-grade PostgreSQL database layer. The design integrates a Third Normal Form (**3NF**) relational schema optimized for multi-service environments (`n8n`, `mcp-server`, `dbmate`, and `backup`). Security is enforced using the Principle of Least Privilege (**PoLP**), Row Level Security (**RLS**), and a Default-Deny Access Control Infrastructure.

---

## Global Database Configuration

- **Timezone**: Set globally to `Africa/Cairo` on initialization via `ALTER DATABASE "$POSTGRES_DB" SET timezone TO 'Africa/Cairo';`.

- **Default Schema**: `public`

- **Identity Generation**: PostgreSQL Native `BIGINT GENERATED ALWAYS AS IDENTITY` for auto-incrementing primary keys.

- **Audit Mechanics**: Automated `updated_at` column timestamping triggered on every row `UPDATE`.

---

## Custom Enumerated Types (ENUMs)

### 1. `lead_status_enum`

Defines the state lifecycle for leads progressing through the conversational sales pipeline:

- `BOT_ACTIVE`: Initial state when an automated bot is handling interaction.

- `NEW`: Newly created lead requiring evaluation.

- `TEMPLATE_SENT`: Initial outreach or outbound template message dispatched.

- `IN_CONVERSATION`: Active engagement between the lead and automated system/agent.

- `QUALIFIED`: Lead successfully evaluated against business qualification criteria.

- `HUMAN_HANDOFF`: Escalated to a human sales or support agent.

- `DISQUALIFIED`: Lead marked as ineligible or non-responsive.

- `ORDER_PLACED`: Lead successfully converted with an associated order.


### 2. `order_status_enum`

Tracks transactional processing stages for orders:

- `PENDING`: Order initialized but not yet confirmed or paid.

- `CONFIRMED`: Order validated and approved.

- `PROCESSING`: Order undergoing fulfillment.

- `DELIVERED`: Order successfully fulfilled and delivered.

- `CANCELLED`: Order terminated.


### 3. `log_sender_enum`

Identifies message authorship within conversation history:

- `USER`: Message sent by the lead/customer.

- `BOT`: Automated AI/System response.

- `AGENT`: Human representative message.

---

## Entity-Relationship & Relational Schema (3NF)

### 1. `public.leads`

Stores core identity and profile metadata for leads.

- **Columns**:

    - `id` (`BIGINT`, `GENERATED ALWAYS AS IDENTITY`, `PRIMARY KEY`)

    - `phone` (`VARCHAR(20)`, `NOT NULL`, `UNIQUE`): **Primary contact handle**.

    - `full_name` (`VARCHAR(255)`)

    - `user_name` (`VARCHAR(255)`)

    - `secondary_phone` (`VARCHAR(20)`)

    - `email` (`VARCHAR(255)`)

    - `platform` (`VARCHAR(50)`, `DEFAULT 'WhatsApp'`)

    - `lead_status` (`lead_status_enum`, `DEFAULT 'BOT_ACTIVE'`)

    - `delivery_address` (`TEXT`)

    - `created_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)

    - `updated_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)


### 2. `public.products`

Catalog of products available for purchase.

- **Columns**:

    - `product_id` (`BIGINT`, `GENERATED ALWAYS AS IDENTITY`, `PRIMARY KEY`)

    - `sku` (`VARCHAR(50)`, `UNIQUE`, `NOT NULL`): **Stock Keeping Unit identifier.**

    - `name` (`VARCHAR(255)`, `NOT NULL`)

    - `price` (`NUMERIC(10, 2)`, `NOT NULL`, `CHECK (price >= 0)`)

    - `description` (`TEXT`)
    
    - `category` (`VARCHAR(100)`, `DEFAULT 'General'`)
    
    - `stock_quantity` (`INT`, `DEFAULT 0`, `CHECK (stock_quantity >= 0)`)
    
    - `is_available` (`BOOLEAN`, `DEFAULT TRUE`)
    
    - `metadata` (`JSONB`, `DEFAULT '{}'::jsonb`): **Unstructured attribute extensions**.
    
    - `created_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)
    
    - `updated_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)


### 3. `public.lead_interests`

Junction table managing many-to-many relationships between leads and products they express interest in.

- **Columns**:

    - `lead_id` (`BIGINT`, `NOT NULL`, `REFERENCES public.leads(id) ON DELETE CASCADE`)
    
    - `product_id` (`BIGINT`, `NOT NULL`, `REFERENCES public.products(product_id) ON DELETE RESTRICT`)
    
    - `created_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)
    
    - `updated_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)


### 4. `public.orders`

Financial and transactional head record for lead purchases.

- **Columns**:

    - `order_id` (`BIGINT`, `GENERATED ALWAYS AS IDENTITY`, `PRIMARY KEY`)

    - `lead_id` (`BIGINT`, `NOT NULL`, `REFERENCES public.leads(id) ON DELETE RESTRICT`)

    - `status` (`order_status_enum`, `DEFAULT 'PENDING'`)

    - `total_amount` (`NUMERIC(10, 2)`, `NOT NULL`, `DEFAULT 0.00`, `CHECK (total_amount >= 0)`)

    - `shipping_address` (`TEXT`)

    - `created_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)

    - `updated_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)


### 5. `public.order_items`

Line-item detail records associated with a specific order.

- **Columns**:

    - `order_item_id` (`BIGINT`, `GENERATED ALWAYS AS IDENTITY`, `PRIMARY KEY`)

    - `order_id` (`BIGINT`, `NOT NULL`, `REFERENCES public.orders(order_id) ON DELETE CASCADE`)

    - `product_id` (`BIGINT`, `NOT NULL`, `REFERENCES public.products(product_id) ON DELETE RESTRICT`)

    - `unit_price` (`NUMERIC(10, 2)`, `NOT NULL`, `CHECK (unit_price >= 0)`)

    - `quantity` (`INT`, `NOT NULL`, `DEFAULT 1`, `CHECK (quantity > 0)`)

    - `created_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)

    - `updated_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)


### 6. `public.conversation_logs`

Chronological interaction logs between leads, automated systems, and human agents.

- **Columns**:

    - `log_id` (`BIGINT`, `GENERATED ALWAYS AS IDENTITY`, `PRIMARY KEY`)

    - `lead_id` (`BIGINT`, `NOT NULL`, `REFERENCES public.leads(id) ON DELETE CASCADE`)

    - `sender` (`log_sender_enum`, `NOT NULL`)

    - `message_content` (`TEXT`, `NOT NULL`)

    - `intent_detected` (`VARCHAR(100)`)

    - `created_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)

    - `updated_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)

### 7. `public.messages`

Message records associated with leads.

- **Columns**:

    - `message_id` (`TEXT`, `PRIMARY KEY`)

    - `lead_id` (`BIGINT`, `NOT NULL`, `REFERENCES leads(id) ON DELETE CASCADE`)
    
    - `message_type` (`TEXT`, `NOT NULL`)
    
    - `content` (`TEXT`, `NOT NULL`)
    
    - `media_id` (`TEXT`)
    
    - `created_at` (`TIMESTAMP`, `DEFAULT NOW()`)
    
    - `updated_at` (`TIMESTAMP`, `DEFAULT NOW()`)

- **Partitioned Messages Table**:

    The `messages` table is engineered using **Range Partitioning** by yearly intervals (`created_at`) to guarantee long-term query performance and seamless data archiving.

    ```SQL
    -- Example for year 2027
    CREATE TABLE IF NOT EXISTS public.messages_y2027 PARTITION OF public.messages
    FOR VALUES FROM ('2027-01-01 00:00:00') TO ('2028-01-01 00:00:00');
    ```
### 8. `public.system_logs`

Dedicated system and technical log repository for monitoring workflow executions, API failures, and runtime exceptions.

- **Columns**:

    - `log_id` (`BIGINT`, `GENERATED ALWAYS AS IDENTITY`, `PRIMARY KEY`)

    - `workflow_id` (`VARCHAR(255)`): **n8n Workflow Execution Context**.

    - `execution_id` (`VARCHAR(255)`): **n8n Runtime Instance Identifier**.

    - `node_name` (`VARCHAR(255)`, `NOT NULL`): **Failing/Originating Node Identifier**.

    - `error_code` (`VARCHAR(100)`): **Technical Error Code** (e.g., `ERR_BAD_REQUEST`, `401`).

    - `error_status` (`VARCHAR(50)`): **HTTP Status / Severity Standard**.

    - `error_message` (`TEXT`, `NOT NULL`): **Exception Narrative / Stack Description**.

    - `error_description ` (`TEXT`)

    - `error_details` (`JSONB`, `DEFAULT '{}'::jsonb`): **Raw Payload Exception State**.

    - `lead_id` (`BIGINT`, `REFERENCES public.leads(id) ON DELETE SET NULL`)

    - `message_id` (`TEXT`)

    - `media_id` (`TEXT`)

    - `created_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)

    - `updated_at` (`TIMESTAMPTZ`, `DEFAULT NOW()`)

---

## Performance Optimization & Indexing Strategy

To maintain sub-millisecond query performance under operational load, indexes are established on high-cardinality foreign keys, lookup fields, and conditional availability flags:

1. `idx_leads_phone`: B-Tree index on `public.leads(phone)` for rapid lookup during incoming webhook triggers.

2. `idx_leads_status`: B-Tree index on `public.leads(lead_status)` for state-based segment querying.

3. `idx_products_sku`: Unique B-Tree index on `public.products(sku)` for inventory lookups.

4. `idx_products_category`: Partial B-Tree index on `public.products(category) WHERE is_available = TRUE` to optimize catalog browsing for available products.

5. `idx_orders_lead_id`: B-Tree index on `public.orders(lead_id)` for retrieving customer order history.

6. `idx_orders_status`: B-Tree index on `public.orders(status)` for order processing workflows.

7. `idx_conversation_logs_lead`: Composite B-Tree index on `public.conversation_logs(lead_id, created_at DESC)` for high-speed chronological chat history reconstruction.

8. `idx_media_id`: B-Tree index on `public.messages(media_id)` for media id lookups.

9. `idx_messages_lead_created_at` Composite B-Tree index on `public.messages (lead_id, created_at DESC)` for high-speed chronological chat history reconstruction.

10. `idx_system_logs_node_name`: B-Tree index on `public.system_logs(node_name)` for system debugging by node.

11. `idx_system_logs_lead_id`: B-Tree index on `public.system_logs(lead_id)` for inspecting error sequences linked to specific leads.

12. `idx_system_logs_created_at`: B-Tree index on `public.system_logs(created_at DESC)` for chronological error monitoring and operational dashboards.

13. `idx_system_logs_error_code`: B-Tree index on `public.system_logs(error_code)` for categorical error frequency aggregation.

---

## Automated Trigger Architecture

An automated procedure updates the `updated_at` field across all transactional tables prior to any `UPDATE` operation.

### Trigger Function Definition

```SQL
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = NOW();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```


### Trigger Attachments

The function is bound via `BEFORE UPDATE ON FOR EACH ROW` triggers across:

- `leads` (`update_leads_updated_at`)

- `products` (`update_products_updated_at`)

- `lead_interests` (`update_lead_interests_updated_at`)

- `orders` (`update_orders_updated_at`)

- `order_items` (`update_order_items_updated_at`)

- `conversation_logs` (`update_conversation_logs_updated_at`)

- `messages` (`update_messages_updated_at`)

- `system_logs` (`update_system_logs_updated_at`)

---

## Role Initialization & Security Architecture (PoLP)

Database initialization (`01-init.sh`) establishes four operational roles with parameterized authentication and strict privilege isolation.

### Infrastructure Baseline

- **Default-Deny Connection**: Direct database connection privileges are revoked from the `PUBLIC` meta-role:

    ```SQL
    REVOKE CONNECT ON DATABASE "$POSTGRES_DB" FROM PUBLIC;
    ```

- **Role Parameterization**: Passwords are injected dynamically through `DO $$` execution blocks utilizing PostgreSQL `%L` formatting to prevent SQL injection vulnerabilities.


### Service Roles Matrix

| Role Name | Login Allowed (`WITH LOGIN`) | Primary Responsibility | Base Privileges (`SCHEMA public`) | Extended Capabilities |
| :--- | :---: | :---: | :---: | :---: |
| `n8n_app_role` | `TRUE` | Workflow Automation Engine | `USAGE`, `CREATE` | Operational Reads/Writes|
| `mcp_app_role` | `TRUE` | Model Context Protocol Server | `USAGE` | Full Operational CRUD |
| `dbmate_app_role` | `TRUE` | Schema Migration Manager | `USAGE`, `CREATE` | DDL Owner / Schema Evolution |
| `backup_app_role` | `TRUE` | Database Backup Utility (`pg_dump`) | `USAGE` | `BYPASSRLS` |


### Default Privileges Evolution

To ensure future-proof schema evolution, object ownership is centered around `dbmate_app_role`. Default privileges automatically grant necessary access to operational roles whenever `dbmate_app_role` creates new tables or sequences:

- **Tables**: `SELECT` granted to `n8n_app_role`, `mcp_app_role`, and `backup_app_role`.

    ```SQL
    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT SELECT ON TABLES TO n8n_app_role;

    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT SELECT ON TABLES TO mcp_app_role;

    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT SELECT ON TABLES TO backup_app_role;
    ```


- **Sequences**: `USAGE`, `SELECT` granted to `n8n_app_role` and `mcp_app_role`; `SELECT` granted to `backup_app_role`.

    ```SQL
    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO n8n_app_role;

    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO mcp_app_role;

    ALTER DEFAULT PRIVILEGES FOR ROLE dbmate_app_role IN SCHEMA public GRANT SELECT ON SEQUENCES TO backup_app_role;

    ```

---

## Table-Level Grants & Row Level Security (RLS)

### Table-Level Permission Map (PoLP Enforcement)

#### `n8n_app_role` Permissions

- **Read-Only (`SELECT`)**: `public.products`

- **Operational Write (`SELECT`, `INSERT`, `UPDATE`)***: `public.leads`, `public.orders`, `public.order_items`, `public.lead_interests`, `public.conversation_logs`, `public.messages`

- **Forbidden**: `DELETE` access on all tables; DDL operations.


#### `mcp_app_role` Permissions

- **Read-Only (`SELECT`)**: `public.products`

- **Full Operational Access (`SELECT`, `INSERT`, `UPDATE`, `DELETE`)**: `public.leads`, `public.orders`, `public.order_items`, `public.lead_interests`, `public.conversation_logs`, `public.messages`

- **Forbidden**: DDL operations.


### Row Level Security (RLS) Configuration

Row Level Security is explicitly enabled on all operational tables

```SQL
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_interests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_logs ENABLE ROW LEVEL SECURITY;
```


### RLS Policy Execution Model

- Operational policies are applied using `FOR ALL` targeting specific application roles.

- `USING (true)` and `WITH CHECK (true)` are configured to allow complete operational visibility within the bounds of table-level `GRANT` statements, while blocking unauthorized role access by default.


### Policies for `n8n_app_role`

- `n8n_leads_policy` ON `public.leads`

- `n8n_orders_policy` ON `public.orders`

- `n8n_order_items_policy` ON `public.order_items`

- `n8n_lead_interests_policy` ON `public.lead_interests`

- `n8n_conversation_logs_policy` ON `public.conversation_logs`

- `n8n_messages_policy` ON `public.messages`

- `n8n_system_logs_policy` ON `public.system_logs`


### Policies for `mcp_app_role`

- `mcp_leads_policy` ON `public.leads`

- `mcp_orders_policy` ON `public.orders`

- `mcp_order_items_policy` ON `public.order_items`

- `mcp_lead_interests_policy` ON `public.lead_interests`

- `mcp_conversation_logs_policy` ON `public.conversation_logs`

- `mcp_messages_policy` ON `public.messages`

- `mcp_system_logs_policy` ON `public.system_logs`

### Backup Isolation (`backup_app_role`)

`backup_app_role` bypasses RLS rules via the `BYPASSRLS` role attribute. This guarantees that database dumps capture entire un-filtered datasets without requiring individual RLS policy evaluation during backup operations.

---

## License

This project is licensed under the MIT License - See [`LICENSE`](../LICENSE) for more information.

---
