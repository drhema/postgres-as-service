import { controlPool, adminPool } from './db';
import { v4 as uuidv4 } from 'uuid';
import * as bcrypt from 'bcrypt';

export interface CreateDatabaseRequest {
  friendlyName: string;
  ownerEmail: string;
  maxConnections?: number;
}

export interface Database {
  id: string;
  database_name: string;
  username: string;
  owner_email: string;
  friendly_name: string;
  max_connections: number;
  status: string;
  created_at: Date;
  updated_at: Date;
}

export interface DatabaseWithCredentials extends Database {
  password: string;
  connection_string: string;
}

export class DatabaseService {

  // Generate unique database and username
  private generateNames() {
    const uniqueId = uuidv4().split('-')[0]; // First part of UUID
    return {
      databaseName: `tenant_${uniqueId}`,
      username: `user_${uniqueId}`,
    };
  }

  // Generate secure random password (alphanumeric only, 12-16 characters)
  private generatePassword(): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    const length = Math.floor(Math.random() * 5) + 12; // Random length between 12-16
    let password = '';
    for (let i = 0; i < length; i++) {
      password += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return password;
  }

  // Create a new database
  async createDatabase(req: CreateDatabaseRequest): Promise<DatabaseWithCredentials> {
    const { databaseName, username } = this.generateNames();
    const password = this.generatePassword();
    const passwordHash = await bcrypt.hash(password, 10);

    const client = await controlPool.connect();
    const adminClient = await adminPool.connect();

    try {
      // 1. Insert into control database (with transaction)
      await client.query('BEGIN');
      const insertResult = await client.query(
        `INSERT INTO databases (database_name, username, password_hash, owner_email, friendly_name, max_connections)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, database_name, username, owner_email, friendly_name, max_connections, status, created_at, updated_at`,
        [databaseName, username, passwordHash, req.ownerEmail, req.friendlyName, req.maxConnections || 20]
      );

      const database = insertResult.rows[0];

      // Log the action in audit_logs
      await client.query(
        `INSERT INTO audit_logs (action, resource_type, resource_id, details)
         VALUES ($1, $2, $3, $4)`,
        ['database_created', 'database', database.id, JSON.stringify({ database_name: databaseName, username })]
      );

      await client.query('COMMIT');

      // 2. Create PostgreSQL user (NO TRANSACTION - must use autocommit)
      await adminClient.query(`CREATE USER ${username} WITH ENCRYPTED PASSWORD '${password}'`);

      // 3. Create PostgreSQL database (NO TRANSACTION - must use autocommit)
      await adminClient.query(`CREATE DATABASE ${databaseName} OWNER ${username}`);

      // 4. Grant privileges (NO TRANSACTION - must use autocommit)
      await adminClient.query(`GRANT ALL PRIVILEGES ON DATABASE ${databaseName} TO ${username}`);

      // Generate all connection string variants (Neon-style)
      const host = process.env.DB_HOST;
      const baseUrl = `postgresql://${username}:${password}@${host}`;

      return {
        ...database,
        password,
        // Direct connection (port 5432)
        connection_string: `${baseUrl}:5432/${databaseName}?sslmode=require`,
        // PgBouncer connection (port 6432 with pgbouncer=true parameter)
        connection_string_pooled: `${baseUrl}:6432/${databaseName}?sslmode=require&pgbouncer=true`,
        // Shadow database URL (same database, for Prisma migrations)
        shadow_database_url: `${baseUrl}:5432/${databaseName}?sslmode=require&schema=public`,
        // Shadow with PgBouncer
        shadow_database_url_pooled: `${baseUrl}:6432/${databaseName}?sslmode=require&schema=public&pgbouncer=true`,
      };

    } catch (error) {
      // Rollback control database transaction if still in progress
      try {
        await client.query('ROLLBACK');
      } catch (e) {
        // Already committed or rolled back
      }

      // Cleanup: try to delete created resources
      try {
        await adminClient.query(`DROP DATABASE IF EXISTS ${databaseName}`);
        await adminClient.query(`DROP USER IF EXISTS ${username}`);
        await client.query('DELETE FROM databases WHERE database_name = $1', [databaseName]);
      } catch (cleanupError) {
        console.error('Cleanup error:', cleanupError);
      }

      throw error;
    } finally {
      client.release();
      adminClient.release();
    }
  }

  // List all databases
  async listDatabases(): Promise<Database[]> {
    const result = await controlPool.query(
      `SELECT id, database_name, username, owner_email, friendly_name, max_connections, status, created_at, updated_at
       FROM databases
       ORDER BY created_at DESC`
    );
    return result.rows;
  }

  // Get database by ID
  async getDatabase(id: string): Promise<Database | null> {
    const result = await controlPool.query(
      `SELECT id, database_name, username, owner_email, friendly_name, max_connections, status, created_at, updated_at
       FROM databases
       WHERE id = $1`,
      [id]
    );
    return result.rows[0] || null;
  }

  // Delete database
  async deleteDatabase(id: string): Promise<void> {
    const client = await controlPool.connect();
    const adminClient = await adminPool.connect();

    try {
      // Get database info
      const dbResult = await client.query(
        'SELECT database_name, username FROM databases WHERE id = $1',
        [id]
      );

      if (dbResult.rows.length === 0) {
        throw new Error('Database not found');
      }

      const { database_name, username } = dbResult.rows[0];

      // Terminate connections (NO TRANSACTION)
      await adminClient.query(
        `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${database_name}'`
      );

      // Drop database (NO TRANSACTION - must use autocommit)
      await adminClient.query(`DROP DATABASE IF EXISTS ${database_name}`);

      // Drop user (NO TRANSACTION - must use autocommit)
      await adminClient.query(`DROP USER IF EXISTS ${username}`);

      // Delete from control database and log (WITH TRANSACTION)
      await client.query('BEGIN');

      await client.query('DELETE FROM databases WHERE id = $1', [id]);

      // Log the action
      await client.query(
        `INSERT INTO audit_logs (action, resource_type, resource_id, details)
         VALUES ($1, $2, $3, $4)`,
        ['database_deleted', 'database', id, JSON.stringify({ database_name, username })]
      );

      await client.query('COMMIT');

    } catch (error) {
      try {
        await client.query('ROLLBACK');
      } catch (e) {
        // Already committed or rolled back
      }
      throw error;
    } finally {
      client.release();
      adminClient.release();
    }
  }

  // Get database statistics
  async getDatabaseStats(id: string): Promise<any> {
    const db = await this.getDatabase(id);
    if (!db) {
      throw new Error('Database not found');
    }

    const result = await adminPool.query(
      `SELECT
        pg_database_size($1) as size_bytes,
        (SELECT count(*) FROM pg_stat_activity WHERE datname = $1) as active_connections
      `,
      [db.database_name]
    );

    return {
      database_id: id,
      database_name: db.database_name,
      size_bytes: parseInt(result.rows[0].size_bytes),
      size_pretty: this.formatBytes(result.rows[0].size_bytes),
      active_connections: result.rows[0].active_connections,
      max_connections: db.max_connections,
    };
  }

  private formatBytes(bytes: number): string {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
  }

  // ===================================================================
  // Get Connection Strings (Neon-style)
  // ===================================================================

  /**
   * Get all connection string variants for a database (Neon-style)
   * Returns direct, pooled, and shadow URLs - all using the same database
   */
  async getConnectionStrings(id: string): Promise<any> {
    const db = await this.getDatabase(id);
    if (!db) {
      throw new Error('Database not found');
    }

    // Get password hash from database
    const result = await controlPool.query(
      'SELECT password_hash FROM databases WHERE id = $1',
      [id]
    );

    const host = process.env.DB_HOST;
    const baseUrl = `postgresql://${db.username}:***@${host}`;

    return {
      database_id: id,
      database_name: db.database_name,
      username: db.username,
      // Direct connection (port 5432)
      connection_string: `${baseUrl}:5432/${db.database_name}?sslmode=require`,
      // PgBouncer connection (port 6432 with pgbouncer=true parameter)
      connection_string_pooled: `${baseUrl}:6432/${db.database_name}?sslmode=require&pgbouncer=true`,
      // Shadow database URL (same database, for Prisma migrations)
      shadow_database_url: `${baseUrl}:5432/${db.database_name}?sslmode=require&schema=public`,
      // Shadow with PgBouncer
      shadow_database_url_pooled: `${baseUrl}:6432/${db.database_name}?sslmode=require&schema=public&pgbouncer=true`,
      note: 'All URLs use the same database. Use ?pgbouncer=true for connection pooling and ?schema=public for Prisma shadow database.'
    };
  }
}
