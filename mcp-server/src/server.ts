import "dotenv/config";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import type { Transport } from "@modelcontextprotocol/sdk/shared/transport.js";
import express from "express";
import type { Request, Response, NextFunction } from "express";
import { z } from "zod";
import crypto from "crypto";
import { pool } from "./db.js";


const app = express();
app.use(express.json());

const MCP_API_KEY = process.env.MCP_API_KEY;

// 1. Middleware to authenticate incoming requests using the MCP API Key
const authenticateMCP = (req: Request, res: Response, next: NextFunction): void => {
//   console.log("=== INCOMING HEADERS ===", JSON.stringify(req.headers, null, 2)); 
//   console.log("Header Key:", req.headers["x-mcp-api-key"], "| Env Key:", process.env.MCP_API_KEY); 
  if (req.path === '/health') {
    return next();
  }

  const providedKey = (req.headers['x-mcp-api-key'] || req.headers['authorization']?.replace('Bearer ', '')) as string | undefined;

  if (!MCP_API_KEY) {
    res.status(500).json({ error: 'Server Security Error: MCP_API_KEY is not configured.' });
    return;
  }

  if (!providedKey) {
    res.status(401).json({ error: 'Unauthorized: Missing MCP API Key.' });
    return;
  }

  const expectedBuffer = Buffer.from(MCP_API_KEY, 'utf8');
  const providedBuffer = Buffer.from(providedKey, 'utf8');

  if (expectedBuffer.length !== providedBuffer.length || !crypto.timingSafeEqual(expectedBuffer, providedBuffer)) {
    res.status(401).json({ error: 'Unauthorized: Invalid MCP API Key.' });
    return;
  }

  next();
};

function createMcpServer() {
    const server = new McpServer({
        name: "PM-Store-Tools",
        version: "1.0.0"
    });

    // 1. Upsert Lead Tool: Insert or update lead information based on phone number
    server.registerTool(
        "upsert_lead",
        {
            description: "Insert a new customer lead or update existing basic info by phone number",
            inputSchema: {
                phone: z.string().describe("Customer phone number"),
                fullName: z.string().optional().describe("Customer full name"),
                userName: z.string().optional().describe("Customer username")
            }
        },
        async ({ phone, fullName, userName }) => {
            try {
                const query = `
                    INSERT INTO public.leads (phone, full_name, user_name, lead_status)
                    VALUES ($1, $2, $3, 'BOT_ACTIVE'::lead_status_enum)
                    ON CONFLICT (phone) 
                    DO UPDATE SET 
                        full_name = COALESCE(EXCLUDED.full_name, leads.full_name),
                        user_name = COALESCE(EXCLUDED.user_name, leads.user_name)
                    RETURNING id, phone, full_name, user_name, lead_status;
                `;
                const res = await pool.query(query, [phone, fullName || null, userName || null]);
                return { content: [{ type: "text", text: JSON.stringify(res.rows[0]) }] };
            } catch (error: any) {
                return { isError: true, content: [{ type: "text", text: `Error in upsert_lead: ${error.message}` }] };
            }
        }
    );

    // 2. Update Lead Info Tool: Update lead personal details, secondary phone, email, or delivery address
    server.registerTool(
        "update_lead_info",
        {
            description: "Update lead personal details, secondary phone, email, or delivery address",
            inputSchema: {
                phone: z.string().describe("Primary customer phone number"),
                fullName: z.string().optional().describe("Customer full name"),
                email: z.string().email().optional().describe("Customer email address"),
                secondaryPhone: z.string().optional().describe("Alternative phone number"),
                deliveryAddress: z.string().optional().describe("Customer delivery address")
            }
        },
        async ({ phone, fullName, email, secondaryPhone, deliveryAddress }) => {
            try {
                const res = await pool.query(
                    `UPDATE public.leads 
                     SET full_name = COALESCE($2, full_name),
                         email = COALESCE($3, email),
                         secondary_phone = COALESCE($4, secondary_phone),
                         delivery_address = COALESCE($5, delivery_address)
                     WHERE phone = $1 
                     RETURNING id, phone, full_name, email, secondary_phone, delivery_address, lead_status`,
                    [phone, fullName || null, email || null, secondaryPhone || null, deliveryAddress || null]
                );

                if (res.rowCount === 0) {
                    return { isError: true, content: [{ type: "text", text: `Lead with phone ${phone} not found` }] };
                }

                return { content: [{ type: "text", text: JSON.stringify(res.rows[0]) }] };
            } catch (error: any) {
                return { isError: true, content: [{ type: "text", text: `Error in update_lead_info: ${error.message}` }] };
            }
        }
    );

    // 3. Update Lead Status Tool: Update lead status in the sales pipeline
    server.registerTool(
        "update_lead_status",
        {
            description: "Update lead status in the sales pipeline",
            inputSchema: {
                phone: z.string().describe("Customer phone number"),
                status: z.enum([
                    'BOT_ACTIVE', 'NEW', 'TEMPLATE_SENT', 'IN_CONVERSATION', 
                    'QUALIFIED', 'HUMAN_HANDOFF', 'DISQUALIFIED', 'ORDER_PLACED'
                ]).describe("New lead status")
            }
        },
        async ({ phone, status }) => {
            try {
                const res = await pool.query(
                    `UPDATE public.leads 
                     SET lead_status = $2::lead_status_enum 
                     WHERE phone = $1 
                     RETURNING id, phone, lead_status`,
                    [phone, status]
                );
                if (res.rowCount === 0) {
                    return { isError: true, content: [{ type: "text", text: `Lead with phone ${phone} not found` }] };
                }
                return { content: [{ type: "text", text: JSON.stringify(res.rows[0]) }] };
            } catch (error: any) {
                return { isError: true, content: [{ type: "text", text: `Error in update_lead_status: ${error.message}` }] };
            }
        }
    );

    // 4. Get Lead Tool: Query lead details, profile, and current status by phone number
    server.registerTool(
        "get_lead",
        {
            description: "Query lead details, profile, and current status by phone number",
            inputSchema: {
                phone: z.string().describe("Customer phone number")
            }
        },
        async ({ phone }) => {
            try {
                const res = await pool.query(
                    `SELECT id, phone, full_name, user_name, email, secondary_phone, platform, lead_status, delivery_address, created_at, updated_at 
                     FROM public.leads WHERE phone = $1 LIMIT 1`,
                    [phone]
                );
                if (res.rowCount === 0) {
                    return { content: [{ type: "text", text: JSON.stringify({ found: false, message: "Lead not found" }) }] };
                }
                return { content: [{ type: "text", text: JSON.stringify({ found: true, lead: res.rows[0] }) }] };
            } catch (error: any) {
                return { isError: true, content: [{ type: "text", text: `Error in get_lead: ${error.message}` }] };
            }
        }
    );

    // 5. Search Products Tool: Search product catalog by name, SKU, or category and check stock availability
    server.registerTool(
        "search_products",
        {
            description: "Search product catalog by name, SKU, or category and check stock availability",
            inputSchema: {
                query: z.string().describe("Search term (product name, category, or SKU)")
            }
        },
        async ({ query }) => {
            try {
                const res = await pool.query(
                    `SELECT product_id, sku, name, price, description, category, stock_quantity, is_available, metadata 
                     FROM public.products 
                     WHERE (name ILIKE $1 OR category ILIKE $1 OR sku ILIKE $1) AND is_available = TRUE`,
                    [`%${query}%`]
                );
                return { content: [{ type: "text", text: JSON.stringify(res.rows) }] };
            } catch (error: any) {
                return { isError: true, content: [{ type: "text", text: `Database error in search_products: ${error.message}` }] };
            }
        }
    );

    // 6. Manage Lead Interest Tool: Link a customer lead with a product they expressed interest in
    server.registerTool(
        "manage_lead_interest",
        {
            description: "Link a customer lead with a product they expressed interest in",
            inputSchema: {
                leadId: z.number().int().describe("Internal database ID of the lead"),
                productId: z.number().int().describe("Internal database ID of the product")
            }
        },
        async ({ leadId, productId }) => {
            try {
                const res = await pool.query(
                    `INSERT INTO public.lead_interests (lead_id, product_id)
                     VALUES ($1, $2)
                     ON CONFLICT DO NOTHING
                     RETURNING lead_id, product_id, created_at`,
                    [leadId, productId]
                );
                return { content: [{ type: "text", text: JSON.stringify(res.rows[0] || { status: "already_recorded", leadId, productId }) }] };
            } catch (error: any) {
                return { isError: true, content: [{ type: "text", text: `Error in manage_lead_interest: ${error.message}` }] };
            }
        }
    );

    // 7. Trigger Order Placed Tool: Create a confirmed order transaction, insert line items, deduct stock, and update lead status to ORDER_PLACED
    server.registerTool(
        "trigger_order_placed",
        {
            description: "Create a confirmed order transaction, insert line items, deduct stock, and update lead status to ORDER_PLACED",
            inputSchema: {
                phone: z.string().describe("Customer phone number"),
                deliveryAddress: z.string().describe("Confirmed shipping/delivery address"),
                items: z.array(z.object({
                    productId: z.number().int().describe("Product ID from catalog"),
                    quantity: z.number().int().positive().describe("Quantity ordered")
                })).min(1).describe("List of ordered items and quantities")
            }
        },
        async ({ phone, deliveryAddress, items }) => {
            const client = await pool.connect();
            try {
                await client.query('BEGIN');

                // a. validate lead existence and retrieve lead ID
                const leadRes = await client.query('SELECT id FROM public.leads WHERE phone = $1', [phone]);
                if (leadRes.rowCount === 0) {
                    throw new Error(`Lead with phone ${phone} not found`);
                }
                const leadId = leadRes.rows[0].id;

                // b. validate product prices and stock from the database (preventing price manipulation by the LLM)
                let totalAmount = 0;
                const verifiedItems: Array<{ productId: number; quantity: number; unitPrice: number }> = [];

                for (const item of items) {
                    const prodRes = await client.query(
                        'SELECT price, stock_quantity, is_available, name FROM public.products WHERE product_id = $1 FOR UPDATE',
                        [item.productId]
                    );
                    if (prodRes.rowCount === 0 || !prodRes.rows[0].is_available) {
                        throw new Error(`Product ID ${item.productId} is unavailable or does not exist.`);
                    }
                    const product = prodRes.rows[0];
                    if (product.stock_quantity < item.quantity) {
                        throw new Error(`Insufficient stock for product "${product.name}". Available: ${product.stock_quantity}, Requested: ${item.quantity}`);
                    }

                    const unitPrice = Number(product.price);
                    totalAmount += unitPrice * item.quantity;
                    verifiedItems.push({ productId: item.productId, quantity: item.quantity, unitPrice });

                    // c. Deduct stock quantity for each product
                    await client.query(
                        'UPDATE public.products SET stock_quantity = stock_quantity - $1 WHERE product_id = $2',
                        [item.quantity, item.productId]
                    );
                }

                // d. Insert the order into the orders table and retrieve the generated order ID
                const orderRes = await client.query(
                    `INSERT INTO public.orders (lead_id, status, total_amount, shipping_address)
                     VALUES ($1, 'PENDING'::order_status_enum, $2, $3) 
                     RETURNING order_id, status, total_amount, created_at`,
                    [leadId, totalAmount, deliveryAddress]
                );
                const order = orderRes.rows[0];

                // e. Insert each verified item into the order_items table
                for (const vItem of verifiedItems) {
                    await client.query(
                        `INSERT INTO public.order_items (order_id, product_id, unit_price, quantity)
                         VALUES ($1, $2, $3, $4)`,
                        [order.order_id, vItem.productId, vItem.unitPrice, vItem.quantity]
                    );
                }

                // f. Update lead status and delivery address
                await client.query(
                    `UPDATE public.leads 
                     SET lead_status = 'ORDER_PLACED'::lead_status_enum, delivery_address = $2 
                     WHERE id = $1`,
                    [leadId, deliveryAddress]
                );

                await client.query('COMMIT');
                return { 
                    content: [{ 
                        type: "text", 
                        text: JSON.stringify({ success: true, order, itemsCount: verifiedItems.length }) 
                    }] 
                };
            } catch (error: any) {
                await client.query('ROLLBACK');
                return { isError: true, content: [{ type: "text", text: `Failed to place order: ${error.message}` }] };
            } finally {
                client.release();
            }
        }
    );

    // 8. Get Lead Orders Tool: Fetch order history and line items for a specific lead ID
    server.registerTool(
        "get_lead_orders",
        {
            description: "Fetch order history and line items for a specific lead ID",
            inputSchema: {
                leadId: z.number().int().describe("The internal database ID of the lead")
            }
        },
        async ({ leadId }) => {
            try {
                const res = await pool.query(
                    `SELECT 
                        o.order_id, o.status, o.total_amount, o.shipping_address, o.created_at,
                        COALESCE(
                            json_agg(
                                json_build_object(
                                    'product_id', oi.product_id,
                                    'product_name', p.name,
                                    'quantity', oi.quantity,
                                    'unit_price', oi.unit_price
                                )
                            ) FILTER (WHERE oi.order_item_id IS NOT NULL), '[]'
                        ) AS items
                     FROM public.orders o
                     LEFT JOIN public.order_items oi ON o.order_id = oi.order_id
                     LEFT JOIN public.products p ON oi.product_id = p.product_id
                     WHERE o.lead_id = $1
                     GROUP BY o.order_id
                     ORDER BY o.created_at DESC`,
                    [leadId]
                );
                return { content: [{ type: "text", text: JSON.stringify(res.rows) }] };
            } catch (error: any) {
                return { isError: true, content: [{ type: "text", text: `Error in get_lead_orders: ${error.message}` }] };
            }
        }
    );

    // 9. Trigger Order Canceled Tool: Cancel a pending/confirmed order, restore stock quantities, and update status to CANCELLED
    server.registerTool(
        "trigger_order_canceled",
        {
            description: "Cancel a pending/confirmed order, restore stock quantities, and update status to CANCELLED",
            inputSchema: {
                orderId: z.number().int().describe("The order ID to cancel"),
                reason: z.string().describe("Reason for cancellation")
            }
        },
        async ({ orderId, reason }) => {
            const client = await pool.connect();
            try {
                await client.query('BEGIN');

                const orderRes = await client.query(
                    `SELECT order_id, lead_id, status FROM public.orders WHERE order_id = $1 FOR UPDATE`,
                    [orderId]
                );
                if (orderRes.rowCount === 0) {
                    throw new Error(`Order ID ${orderId} not found`);
                }
                const order = orderRes.rows[0];
                if (order.status === 'CANCELLED' || order.status === 'DELIVERED') {
                    throw new Error(`Cannot cancel order in status ${order.status}`);
                }

                // Restore stock quantities for each item in the order
                const itemsRes = await client.query(
                    'SELECT product_id, quantity FROM public.order_items WHERE order_id = $1',
                    [orderId]
                );
                for (const item of itemsRes.rows) {
                    await client.query(
                        'UPDATE public.products SET stock_quantity = stock_quantity + $1 WHERE product_id = $2',
                        [item.quantity, item.product_id]
                    );
                }

                // Update order status to CANCELLED (according to order_status_enum)
                await client.query(
                    `UPDATE public.orders SET status = 'CANCELLED'::order_status_enum WHERE order_id = $1`,
                    [orderId]
                );

                // Update lead status to IN_CONVERSATION for continued conversation
                await client.query(
                    `UPDATE public.leads SET lead_status = 'IN_CONVERSATION'::lead_status_enum WHERE id = $1`,
                    [order.lead_id]
                );

                await client.query('COMMIT');
                return { content: [{ type: "text", text: `Order #${orderId} canceled and stock restored. Reason: ${reason}` }] };
            } catch (error: any) {
                await client.query('ROLLBACK');
                return { isError: true, content: [{ type: "text", text: `Error in trigger_order_canceled: ${error.message}` }] };
            } finally {
                client.release();
            }
        }
    );

    // 10. Trigger Human Handoff Tool: Escalate conversation and transfer lead status to HUMAN_HANDOFF
    server.registerTool(
        "trigger_human_handoff",
        {
            description: "Escalate conversation and transfer lead status to HUMAN_HANDOFF",
            inputSchema: {
                phone: z.string().describe("Customer phone number"),
                reason: z.string().describe("Reason for escalating to human support")
            }
        },
        async ({ phone, reason }) => {
            try {
                const res = await pool.query(
                    `UPDATE public.leads 
                     SET lead_status = 'HUMAN_HANDOFF'::lead_status_enum 
                     WHERE phone = $1 RETURNING id`,
                    [phone]
                );
                if (res.rowCount === 0) {
                    return { isError: true, content: [{ type: "text", text: `Lead with phone ${phone} not found` }] };
                }
                return { content: [{ type: "text", text: `Handoff triggered for lead #${res.rows[0].id}. Reason: ${reason}` }] };
            } catch (error: any) {
                return { isError: true, content: [{ type: "text", text: `Error in trigger_human_handoff: ${error.message}` }] };
            }
        }
    );

    // 11. Log Interaction Tool: Save a conversation message log to history with sender role and detected intent
    server.registerTool(
        "log_interaction",
        {
            description: "Save a conversation message log to history with sender role and detected intent",
            inputSchema: {
                leadId: z.number().int().describe("Internal database ID of the lead"),
                sender: z.enum(['USER', 'BOT', 'AGENT']).describe("Author of the message"),
                messageContent: z.string().describe("Text content of the message"),
                intentDetected: z.string().optional().describe("Classified intent of the message")
            }
        },
        async ({ leadId, sender, messageContent, intentDetected }) => {
            try {
                const res = await pool.query(
                    `INSERT INTO public.conversation_logs (lead_id, sender, message_content, intent_detected)
                     VALUES ($1, $2::log_sender_enum, $3, $4)
                     RETURNING log_id, created_at`,
                    [leadId, sender, messageContent, intentDetected || null]
                );
                return { content: [{ type: "text", text: JSON.stringify(res.rows[0]) }] };
            } catch (error: any) {
                return { isError: true, content: [{ type: "text", text: `Error in log_interaction: ${error.message}` }] };
            }
        }
    );

    // 12. Get Conversation History Tool: Retrieve recent chronological conversation messages for context
    server.registerTool(
        "get_conversation_history",
        {
            description: "Retrieve recent chronological conversation messages for context",
            inputSchema: {
                leadId: z.number().int().describe("Internal database ID of the lead"),
                limit: z.number().int().min(1).max(50).default(15).describe("Number of recent messages to fetch")
            }
        },
        async ({ leadId, limit }) => {
            try {
                const res = await pool.query(
                    `SELECT log_id, sender, message_content, intent_detected, created_at 
                     FROM public.conversation_logs 
                     WHERE lead_id = $1 
                     ORDER BY created_at DESC 
                     LIMIT $2`,
                    [leadId, limit]
                );
                // Return the messages in chronological order (oldest first)
                return { content: [{ type: "text", text: JSON.stringify(res.rows.reverse()) }] };
            } catch (error: any) {
                return { isError: true, content: [{ type: "text", text: `Error in get_conversation_history: ${error.message}` }] };
            }
        }
    );

    return server;
}

const server = createMcpServer();
// Store active sessions for each connected client
const transports = new Map<string, StreamableHTTPServerTransport>();

app.all("/mcp", authenticateMCP, async (req: Request, res: Response) => {
    try {
        const sessionId = req.headers["mcp-session-id"] as string | undefined;
        let transport: StreamableHTTPServerTransport;

        if (sessionId && transports.has(sessionId)) {
            // 1. Retrieve the existing session for subsequent requests (notifications/initialized, tools/list, tools/call)
            transport = transports.get(sessionId)!;
        } else if (!sessionId && req.method === "POST") {
            // 2. Create a new session when the first initialization request is received (initialize)
            transport = new StreamableHTTPServerTransport({
                sessionIdGenerator: () => crypto.randomUUID(),
                onsessioninitialized: (newSessionId) => {
                    transports.set(newSessionId, transport);
                }
            });

            // Clean up the session from memory when the connection is closed
            transport.onclose = () => {
                if (transport.sessionId) {
                    transports.delete(transport.sessionId);
                }
            };

            const mcpServer = createMcpServer();
            await mcpServer.connect(transport as Transport);
        } else {
            // 3. If no valid session ID is provided and it's not an initialization request, return an error
            res.status(400).json({
                jsonrpc: "2.0",
                error: { code: -32000, message: "Bad Request: No valid session ID provided" },
                id: null
            });
            return;
        }

        await transport.handleRequest(req, res, req.body);
    } catch (error: any) {
        console.error("MCP Transport Error:", error);
        if (!res.headersSent) {
            res.status(500).json({
                jsonrpc: "2.0",
                error: { code: -32603, message: `Internal error: ${error.message}` },
                id: null
            });
        }
    }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'mcp-server-native' });
});

const PORT = process.env.PORT || process.env.MCP_SERVER_PORT;
app.listen(Number(PORT), "0.0.0.0", () => {
    console.log(`[Native MCP Server]: Running on http://localhost:${PORT}/mcp`);
});