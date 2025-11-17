import { controlPool, adminPool } from './db';
import * as fs from 'fs/promises';
import { exec } from 'child_process';
import { promisify } from 'util';

const execPromise = promisify(exec);

export interface AddIPWhitelistRequest {
  ipAddress: string;
  description?: string;
}

export interface IPWhitelist {
  id: number;
  database_id: string;
  ip_address: string;
  description: string | null;
  added_at: Date;
}

export class WhitelistService {

  // Validate IP address format (supports CIDR)
  private validateIPAddress(ip: string): boolean {
    // CIDR format: xxx.xxx.xxx.xxx/xx or single IP
    const cidrRegex = /^(\d{1,3}\.){3}\d{1,3}(\/\d{1,2})?$/;

    if (!cidrRegex.test(ip)) {
      return false;
    }

    // Validate each octet
    const parts = ip.split('/')[0].split('.');
    return parts.every(part => {
      const num = parseInt(part);
      return num >= 0 && num <= 255;
    });
  }

  // Add IP to whitelist
  async addIP(databaseId: string, req: AddIPWhitelistRequest): Promise<IPWhitelist> {
    const client = await controlPool.connect();

    try {
      // Validate IP format
      if (!this.validateIPAddress(req.ipAddress)) {
        throw new Error('Invalid IP address format. Use xxx.xxx.xxx.xxx/xx or xxx.xxx.xxx.xxx/32 for single IP');
      }

      // Check if database exists
      const dbCheck = await client.query(
        'SELECT database_name FROM databases WHERE id = $1',
        [databaseId]
      );

      if (dbCheck.rows.length === 0) {
        throw new Error('Database not found');
      }

      // Add IP to whitelist
      await client.query('BEGIN');

      const result = await client.query(
        `INSERT INTO ip_whitelist (database_id, ip_address, description)
         VALUES ($1, $2, $3)
         RETURNING id, database_id, ip_address, description, added_at`,
        [databaseId, req.ipAddress, req.description || null]
      );

      const whitelist = result.rows[0];

      // Log the action
      await client.query(
        `INSERT INTO audit_logs (action, resource_type, resource_id, details)
         VALUES ($1, $2, $3, $4)`,
        ['ip_whitelist_added', 'database', databaseId, JSON.stringify({ ip_address: req.ipAddress })]
      );

      await client.query('COMMIT');

      // Update pg_hba.conf
      await this.updatePgHbaConf();

      return whitelist;

    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  // List IPs for a database
  async listIPs(databaseId: string): Promise<IPWhitelist[]> {
    const result = await controlPool.query(
      `SELECT id, database_id, ip_address, description, added_at
       FROM ip_whitelist
       WHERE database_id = $1
       ORDER BY added_at DESC`,
      [databaseId]
    );

    return result.rows;
  }

  // Remove IP from whitelist
  async removeIP(databaseId: string, whitelistId: number): Promise<void> {
    const client = await controlPool.connect();

    try {
      await client.query('BEGIN');

      // Get IP before deleting
      const ipResult = await client.query(
        'SELECT ip_address FROM ip_whitelist WHERE id = $1 AND database_id = $2',
        [whitelistId, databaseId]
      );

      if (ipResult.rows.length === 0) {
        throw new Error('IP whitelist entry not found');
      }

      const { ip_address } = ipResult.rows[0];

      // Delete from whitelist
      await client.query(
        'DELETE FROM ip_whitelist WHERE id = $1 AND database_id = $2',
        [whitelistId, databaseId]
      );

      // Log the action
      await client.query(
        `INSERT INTO audit_logs (action, resource_type, resource_id, details)
         VALUES ($1, $2, $3, $4)`,
        ['ip_whitelist_removed', 'database', databaseId, JSON.stringify({ ip_address })]
      );

      await client.query('COMMIT');

      // Update pg_hba.conf
      await this.updatePgHbaConf();

    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  // Update pg_hba.conf file with current whitelist rules
  private async updatePgHbaConf(): Promise<void> {
    try {
      // Get all databases with IP whitelists
      const result = await controlPool.query(`
        SELECT
          d.database_name,
          d.username,
          iw.ip_address
        FROM databases d
        LEFT JOIN ip_whitelist iw ON d.id = iw.database_id
        WHERE d.status = 'active'
        ORDER BY d.database_name, iw.id
      `);

      // Group by database
      const dbRules: { [key: string]: { username: string; ips: string[] } } = {};

      result.rows.forEach(row => {
        if (!dbRules[row.database_name]) {
          dbRules[row.database_name] = {
            username: row.username,
            ips: []
          };
        }
        if (row.ip_address) {
          dbRules[row.database_name].ips.push(row.ip_address);
        }
      });

      // Build managed section
      let managedSection = '';

      Object.entries(dbRules).forEach(([dbName, { username, ips }]) => {
        if (ips.length > 0) {
          managedSection += `\n# Rules for ${dbName}\n`;
          ips.forEach(ip => {
            managedSection += `hostssl ${dbName}             ${username}             ${ip}                    scram-sha-256\n`;
          });
          // Add reject rule for all other IPs
          managedSection += `host    ${dbName}             ${username}             0.0.0.0/0               reject\n`;
          managedSection += `host    ${dbName}             ${username}             ::/0                    reject\n`;
        }
      });

      // Read current pg_hba.conf
      const pgHbaPath = '/etc/postgresql/16/main/pg_hba.conf';
      const content = await fs.readFile(pgHbaPath, 'utf-8');

      // Replace managed section
      const startMarker = '### API_MANAGED_SECTION_START ###';
      const endMarker = '### API_MANAGED_SECTION_END ###';

      const startIndex = content.indexOf(startMarker);
      const endIndex = content.indexOf(endMarker);

      if (startIndex === -1 || endIndex === -1) {
        throw new Error('API managed section markers not found in pg_hba.conf');
      }

      const newContent =
        content.substring(0, startIndex + startMarker.length) +
        managedSection +
        '\n' +
        content.substring(endIndex);

      // Write updated content
      await fs.writeFile(pgHbaPath, newContent, 'utf-8');

      // Reload PostgreSQL configuration
      await execPromise('sudo systemctl reload postgresql');

      console.log('✓ pg_hba.conf updated and PostgreSQL reloaded');

    } catch (error) {
      console.error('Error updating pg_hba.conf:', error);
      throw new Error('Failed to update PostgreSQL configuration');
    }
  }
}
