import pkg from "pg";
const { Pool } = pkg;

// Check for required environment variables for database connection
const requiredEnvs = ["DB_HOST", "DB_PORT", "DB_USER", "DB_PASSWORD", "DB_NAME"];
for (const env of requiredEnvs) {
  if (!process.env[env]) {
    throw new Error(`[Database Error]: Environment variable ${env} is missing.`);
  }
}

// Create a new PostgreSQL connection pool
export const pool = new Pool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  max: 10, 
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Handle unexpected errors on the PostgreSQL client
pool.on("error", (err) => {
  console.error("Unexpected error on idle PostgreSQL client", err);
  process.exit(-1);
});