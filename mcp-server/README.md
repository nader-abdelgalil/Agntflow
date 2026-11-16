# Native Model Context Protocol (MCP) Server — PM-Store-Tools

## Overview

**PM-Store-Tools** is a standardized **Model Context Protocol (MCP)** server built with TypeScript, Express, and `@modelcontextprotocol/sdk`. It acts as a secure, transactional service layer bridging AI agents with a PostgreSQL Database.

Instead of exposing raw SQL execution to Large Language Models (LLMs), this server enforces strict input validation via **Zod**, constant-time API key authentication, server-side price/inventory verification, and ACID-compliant database transactions.

---

## System Architecture

```text
┌───────────────────┐      Streamable HTTP / JSON-RPC      ┌──────────────────────────┐
│   n8n AI Agent    │ ───────────────────────────────────► │   Native MCP Server      │
│  (MCP Client)     │   POST /mcp + x-mcp-api-key Header   │   (Express + MCP SDK)    │
└───────────────────┘                                      └────────────┬─────────────┘
                                                                        │
                                                         Parameterized SQL & Transactions
                                                         (Role: mcp_app_role / PoLP + RLS)
                                                                        │
                                                                        ▼
                                                           ┌──────────────────────────┐
                                                           │   PostgreSQL Database    │
                                                           │   (3NF Schema + Locks)   │
                                                           └──────────────────────────┘
```

### Key Architectural Highlights
* **Standardized Protocol**: Uses `McpServer` and `StreamableHTTPServerTransport` on `/mcp` for native dynamic tool discovery and standardized error envelopes (`isError: true`).
* **Zero-Trust LLM Pricing & Stock Protection**: Product unit prices and available stock are never trusted from LLM payloads. The server locks product rows (`SELECT ... FOR UPDATE`), verifies live prices and inventory, deducts stock, and commits line items atomically.
* **ACID Transactional Integrity**: Multi-table operations (`trigger_order_placed`, `trigger_order_canceled`) execute inside explicit `BEGIN / COMMIT / ROLLBACK` blocks using dedicated pooled connections.
* **Timing-Safe Authentication**: Protects the `/mcp` endpoint using `crypto.timingSafeEqual` against `MCP_API_KEY`.

---

## Database Role Permissions Note
Ensure the PostgreSQL service role (`mcp_app_role`) has the required grants:
* `SELECT, INSERT, UPDATE, DELETE` on `leads`, `orders`, `order_items`, `lead_interests`, `conversation_logs`, `messages`.
* `SELECT` on `products`, plus `UPDATE (stock_quantity)` on `public.products` to allow atomic inventory deduction and restoration during order placement/cancellation.

---

## Endpoints

| Method | Path | Auth Required | Description |
| :--- | :--- | :---: | :--- |
| `ALL` | `/mcp` | **Yes** (`x-mcp-api-key` or `Bearer`) | Main MCP JSON-RPC / Streamable HTTP transport endpoint for tool discovery and execution. |
| `GET` | `/health` | No | Container health check endpoint returning `{ "status": "ok", "service": "mcp-server-native" }`. |

---

## Registered MCP Tools Reference (12 Tools)

### 1. Lead Management Tools

#### `upsert_lead`
Creates a new lead record with initial status `BOT_ACTIVE` or updates existing basic profile fields if the phone number already exists.
* **Target Table**: `public.leads`
* **Input Schema**:
  * `phone` (`string`, required): Primary contact phone number.
  * `fullName` (`string`, optional): Customer's full name.
  * `userName` (`string`, optional): Platform handle/username.

#### `update_lead_info`
Updates extended profile attributes and delivery details for an existing lead without overwriting omitted fields (`COALESCE`).
* **Target Table**: `public.leads`
* **Input Schema**:
  * `phone` (`string`, required): Primary contact phone number.
  * `fullName` (`string`, optional): Customer's full name.
  * `email` (`string`, optional, email format): Customer's email address.
  * `secondaryPhone` (`string`, optional): Backup phone number.
  * `deliveryAddress` (`string`, optional): Shipping/delivery address.

#### `update_lead_status`
Transitions a lead through the sales pipeline lifecycle (`lead_status_enum`).
* **Target Table**: `public.leads`
* **Input Schema**:
  * `phone` (`string`, required): Primary contact phone number.
  * `status` (`enum`, required): One of `BOT_ACTIVE`, `NEW`, `TEMPLATE_SENT`, `IN_CONVERSATION`, `QUALIFIED`, `HUMAN_HANDOFF`, `DISQUALIFIED`, `ORDER_PLACED`.

#### `get_lead`
Retrieves full profile metadata, delivery address, and current pipeline status by phone number.
* **Target Table**: `public.leads`
* **Input Schema**:
  * `phone` (`string`, required): Primary contact phone number.

---

### 2. Product Catalog & Interest Tools

#### `search_products`
Searches active catalog items (`is_available = TRUE`) using case-insensitive pattern matching (`ILIKE`) across product name, category, and SKU.
* **Target Table**: `public.products`
* **Input Schema**:
  * `query` (`string`, required): Search keyword or SKU.

#### `manage_lead_interest`
Records a many-to-many link between a lead and a product they inquired about (idempotent via `ON CONFLICT DO NOTHING`).
* **Target Table**: `public.lead_interests`
* **Input Schema**:
  * `leadId` (`integer`, required): Internal database ID of the lead.
  * `productId` (`integer`, required): Internal database ID of the product.

---

### 3. Order & Inventory Transaction Tools

#### `trigger_order_placed`
Executes a full ACID transaction to place a customer order:
1. Verifies the lead exists.
2. Locks requested product rows (`FOR UPDATE`), validates availability and `stock_quantity`, fetches authoritative `price`, and deducts stock.
3. Creates the order header in `public.orders` with status `PENDING`.
4. Inserts line items into `public.order_items`.
5. Updates `public.leads` status to `ORDER_PLACED` and saves `delivery_address`.
* **Target Tables**: `public.leads`, `public.products`, `public.orders`, `public.order_items`
* **Input Schema**:
  * `phone` (`string`, required): Customer phone number.
  * `deliveryAddress` (`string`, required): Confirmed shipping address.
  * `items` (`array`, min 1, required): List of `{ productId: number, quantity: number }`.

#### `get_lead_orders`
Fetches a lead's complete order history aggregated with nested JSON arrays of line items and product names.
* **Target Tables**: `public.orders`, `public.order_items`, `public.products`
* **Input Schema**:
  * `leadId` (`integer`, required): Internal database ID of the lead.

#### `trigger_order_canceled`
Atomically cancels a non-delivered order, restores deducted quantities back to `public.products.stock_quantity`, sets order status to `CANCELLED`, and resets lead status to `IN_CONVERSATION`.
* **Target Tables**: `public.orders`, `public.order_items`, `public.products`, `public.leads`
* **Input Schema**:
  * `orderId` (`integer`, required): Internal order ID to cancel.
  * `reason` (`string`, required): Reason for cancellation.

---

### 4. Escalation & Conversation Logging Tools

#### `trigger_human_handoff`
Escalates the conversation by setting the lead's status to `HUMAN_HANDOFF` so automated workflows pause and human agents take over.
* **Target Table**: `public.leads`
* **Input Schema**:
  * `phone` (`string`, required): Customer phone number.
  * `reason` (`string`, required): Escalation reason.

#### `log_interaction`
Persists a single conversation turn into chronological storage with authorship and intent metadata.
* **Target Table**: `public.conversation_logs`
* **Input Schema**:
  * `leadId` (`integer`, required): Internal database ID of the lead.
  * `sender` (`enum`, required): `USER`, `BOT`, or `AGENT`.
  * `messageContent` (`string`, required): Message text.
  * `intentDetected` (`string`, optional): Classified user intent.

#### `get_conversation_history`
Fetches the most recent messages for a lead (up to 50) ordered chronologically (`ASC`) to supply conversational context to the LLM.
* **Target Table**: `public.conversation_logs`
* **Input Schema**:
  * `leadId` (`integer`, required): Internal database ID of the lead.
  * `limit` (`integer`, optional, default `15`, min `1`, max `50`): Number of messages to retrieve.

---

## Integration Guide (n8n MCP Client)

1. Add an **AI Agent** node in your n8n workflow.
2. Attach the **MCP Client Tool** node to the AI Agent's `Tools` port.
3. Configure the MCP Client Tool:
   * **Transport**: `HTTP Streamable`
   * **Server URL**: `http://pm-mcp-server:3001/mcp` (or your Docker service/host URL)
   * **Authentication / Headers**: Add header `x-mcp-api-key` with your configured `MCP_API_KEY`.
4. The n8n AI Agent will automatically discover all 12 tools, inspect their Zod schemas, and invoke them dynamically based on customer interactions.

---

## Build & Deployment

```bash
# Install dependencies
npm install

# Compile TypeScript to JavaScript
npm run build

# Start in production mode
npm start

# Or deploy via Docker Compose
docker compose up --build -d
```