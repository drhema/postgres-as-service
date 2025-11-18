import { Pool } from 'pg';
import * as dotenv from 'dotenv';

dotenv.config();

// Determine which port to use
// If PgBouncer is enabled, use port 6432 (connection pooling)
// Otherwise, use port 5432 (direct PostgreSQL connection)
const DB_PGBOUNCER_ENABLED = process.env.DB_PGBOUNCER_ENABLED === 'true';
const DB_PGBOUNCER_PORT = parseInt(process.env.DB_PGBOUNCER_PORT || '6432');
const DB_DIRECT_PORT = parseInt(process.env.DB_PORT || '5432');

// Use PgBouncer port if enabled, otherwise direct connection
const connectionPort = DB_PGBOUNCER_ENABLED ? DB_PGBOUNCER_PORT : DB_DIRECT_PORT;

// Log connection mode
console.log(`Database connection mode: ${DB_PGBOUNCER_ENABLED ? 'PgBouncer (port 6432)' : 'Direct (port 5432)'}`);

// Control database connection pool
// When using PgBouncer, we can handle more connections since PgBouncer multiplexes them
export const controlPool = new Pool({
  host: process.env.DB_HOST,
  port: connectionPort,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
  max: DB_PGBOUNCER_ENABLED ? 100 : 20, // Higher limit when using PgBouncer
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Admin connection pool (for creating databases and users)
// Admin operations always use direct PostgreSQL connection (not through PgBouncer)
// This ensures DDL operations work correctly
export const adminPool = new Pool({
  host: process.env.DB_HOST,
  port: DB_DIRECT_PORT, // Always use direct port for admin operations
  user: process.env.PG_ADMIN_USER,
  password: process.env.PG_ADMIN_PASSWORD,
  database: 'postgres',
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
  max: 50, // Increased for better admin operation concurrency
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Test connection
controlPool.on('connect', () => {
  console.log('✓ Connected to control database');
});

controlPool.on('error', (err) => {
  console.error('Control database error:', err);
});

adminPool.on('connect', () => {
  console.log('✓ Connected to admin database');
});

adminPool.on('error', (err) => {
  console.error('Admin database error:', err);
});
