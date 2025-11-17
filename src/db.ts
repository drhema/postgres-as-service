import { Pool } from 'pg';
import * as dotenv from 'dotenv';

dotenv.config();

// Control database connection pool
export const controlPool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT || '5432'),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Admin connection pool (for creating databases and users)
export const adminPool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT || '5432'),
  user: process.env.PG_ADMIN_USER,
  password: process.env.PG_ADMIN_PASSWORD,
  database: 'postgres',
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
  max: 5,
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
