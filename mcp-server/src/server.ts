import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import type { Transport } from "@modelcontextprotocol/sdk/shared/transport.js";
import express from "express";
import type { Request, Response } from "express";
import { z } from "zod";
import { pool } from "./db.js";

const app = express();

function createMcpServer() {
    const server = new McpServer({
        name: "PM-Store-Tools",
        version: "1.0.0"
    });

    // 1. أداة البحث في الكتالوج
    server.registerTool(
        "search_products",
        {
            description: "Search product catalog by name or category",
            inputSchema: {
                query: z.string().describe("Search term")
            }
        },
        async ({ query }) => {
            try {
                const res = await pool.query(
                    `SELECT product_id, name, price, description, is_available 
           FROM products 
           WHERE (name ILIKE $1 OR category ILIKE $1) AND is_available = TRUE`,
                    [`%${query}%`]
                );
                return { content: [{ type: "text", text: JSON.stringify(res.rows) }] };
            } catch (error: any) {
                return {
                    isError: true,
                    content: [{ type: "text", text: `Database error in search_products: ${error.message}` }]
                };
            }
        }
    );

    // 2. أداة تحديث بيانات العميل
    server.registerTool(
        "update_lead_info",
        {
            description: "Update lead personal info",
            inputSchema: {
                phone: z.string().describe("Customer phone number"),
                full_name: z.string().optional().describe("Customer full name"),
                delivery_address: z.string().optional().describe("Customer delivery address")
            }
        },
        async ({ phone, full_name, delivery_address }) => {
            try {
                const res = await pool.query(
                    `UPDATE leads 
           SET full_name = COALESCE($2, full_name), 
               delivery_address = COALESCE($3, delivery_address)
           WHERE phone = $1`,
                    [phone, full_name, delivery_address]
                );

                if (res.rowCount === 0) {
                    return {
                        isError: true,
                        content: [{ type: "text", text: `Lead with phone ${phone} not found` }]
                    };
                }

                return { content: [{ type: "text", text: "Lead info updated successfully" }] };
            } catch (error: any) {
                return {
                    isError: true,
                    content: [{ type: "text", text: `Database error in update_lead_info: ${error.message}` }]
                };
            }
        }
    );

    // 3. أداة تأكيد الطلب
    server.registerTool(
        "trigger_order_placed",
        {
            description: "Confirm customer order and set status to ORDER_PLACED",
            inputSchema: {
                phone: z.string().describe("Customer phone number"),
                items: z.array(z.object({
                    product_id: z.string(),
                    quantity: z.number()
                })).describe("List of ordered items and quantities"),
                delivery_address: z.string().describe("Confirmed delivery address")
            }
        },
        async ({ phone, items, delivery_address }) => {
            const client = await pool.connect();
            try {
                await client.query('BEGIN');

                const res = await client.query(
                    "UPDATE leads SET lead_status = 'ORDER_PLACED', delivery_address = $2 WHERE phone = $1",
                    [phone, delivery_address]
                );

                if (res.rowCount === 0) {
                    throw new Error(`Lead with phone ${phone} not found`);
                }

                await client.query('COMMIT');
                const itemDetails = items.map(i => `${i.product_id} (x${i.quantity})`).join(", ");
                return { content: [{ type: "text", text: `Order placed for items [${itemDetails}] & status updated to ORDER_PLACED` }] };
            } catch (error: any) {
                await client.query('ROLLBACK');
                return {
                    isError: true,
                    content: [{ type: "text", text: `Failed to place order: ${error.message}` }]
                };
            } finally {
                client.release();
            }
        }
    );

    // 4. أداة التحويل البشري
    server.registerTool(
        "trigger_human_handoff",
        {
            description: "Trigger handoff to human support agent",
            inputSchema: {
                phone: z.string().describe("Customer phone number"),
                reason: z.string().describe("Reason for handoff")
            }
        },
        async ({ phone, reason }) => {
            try {
                const res = await pool.query(
                    "UPDATE leads SET lead_status = 'HUMAN_HANDOFF' WHERE phone = $1",
                    [phone]
                );

                if (res.rowCount === 0) {
                    return {
                        isError: true,
                        content: [{ type: "text", text: `Lead with phone ${phone} not found` }]
                    };
                }

                return { content: [{ type: "text", text: `Handoff triggered successfully. Reason: ${reason}` }] };
            } catch (error: any) {
                return {
                    isError: true,
                    content: [{ type: "text", text: `Error in trigger_human_handoff: ${error.message}` }]
                };
            }
        }
    );

    // 5. أداة إلغاء الطلب
    server.registerTool(
        "trigger_order_canceled",
        {
            description: "Cancel order and update lead status in database",
            inputSchema: {
                phone: z.string().describe("Customer phone number"),
                reason: z.string().describe("Reason for cancellation")
            }
        },
        async ({ phone, reason }) => {
            try {
                const res = await pool.query(
                    "UPDATE leads SET lead_status = 'ORDER_CANCELED' WHERE phone = $1",
                    [phone]
                );

                if (res.rowCount === 0) {
                    return {
                        isError: true,
                        content: [{ type: "text", text: `Lead with phone ${phone} not found` }]
                    };
                }

                return { content: [{ type: "text", text: `Order canceled successfully. Reason: ${reason}` }] };
            } catch (error: any) {
                return {
                    isError: true,
                    content: [{ type: "text", text: `Error in trigger_order_canceled: ${error.message}` }]
                };
            }
        }
    );

    return server;
}

app.all("/mcp", async (req: Request, res: Response) => {
    try {
        const server = createMcpServer();
        const transport = new StreamableHTTPServerTransport();
        await server.connect(transport as Transport);
        await transport.handleRequest(req, res);
    } catch (error: any) {
        console.error("MCP Transport Error:", error);
        if (!res.headersSent) {
            res.status(500).send(`MCP Transport Error: ${error.message}`);
        }
    }
});

app.listen(3001, "0.0.0.0", () => {
    console.log(`MCP server is running on http://localhost:3001/mcp`);
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});