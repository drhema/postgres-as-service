# PostgreSQL Multi-Tenant SaaS Platform

Complete PostgreSQL-as-a-Service platform with REST API for database provisioning, SSL/TLS encryption, and per-database IP whitelisting.

## Features

- ✅ PostgreSQL 16 with SSL/TLS (Let's Encrypt)
- ✅ Multi-tenant database isolation
- ✅ REST API for database management
- ✅ Per-database IP whitelisting (optional)
- ✅ Automatic SSL certificate renewal
- ✅ Database statistics and monitoring
- ✅ Audit logging
- ✅ Daily automated backups

## Table of Contents

1. [Server Installation](#server-installation)
2. [API Setup](#api-setup)
3. [API Usage](#api-usage)
4. [IP Whitelisting](#ip-whitelisting)
5. [Management](#management)
6. [Security](#security)

---

## Server Installation

### Prerequisites

- Ubuntu 24.04 server
- Root or sudo access
- Domain name pointing to your server (e.g., `db.yourdomain.com`)
- Ports 80, 5432, and 22 open in your firewall

### Step 1: Download Installation Script

```bash
# SSH into your server
ssh root@your-server-ip

# Download the installation script
curl -o postgres.sh https://gist.githubusercontent.com/drhema/bece21fefd4c988c44a5443d308ecd71/raw/postgres.sh
OR
curl -o postgres.sh https://raw.githubusercontent.com/drhema/postgres-as-service/refs/heads/main/postgres.sh
# Make it executable
chmod +x postgres.sh
```

### Step 2: Run Installation

```bash
sudo ./postgres.sh
```

The script will prompt you for:
- **Domain name**: `db.yourdomain.com` (must point to your server's IP)
- **Email**: For Let's Encrypt SSL certificate notifications
- **PostgreSQL password**: Strong password (min 12 characters)

### Step 3: Installation Process

The script will automatically:
1. Update system packages
2. Install PostgreSQL 16
3. Install dependencies (certbot, curl, etc.)
4. Obtain SSL certificate from Let's Encrypt
5. Configure PostgreSQL with SSL
6. Create control database with schema
7. Set up auto-renewal for SSL certificates
8. Create management utilities
9. Configure daily backups

### Step 4: Verify Installation

```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Test connection
sudo -u postgres psql -c "SELECT version();"

# View management commands
pg-status
```

### Installation Output

Save the installation summary which includes:
- Server IP and domain
- Database credentials
- Connection strings
- SSL certificate locations
- Management commands

---

## API Setup

### Step 1: Install Dependencies

On your **local machine** or **API server**:

```bash
cd api

# Install Node.js dependencies
npm install
```

### Step 2: Configure Environment

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env with your credentials
nano .env
```

**Update `.env` with your values:**

```env
# PostgreSQL Control Database Connection
DB_HOST=db.yourdomain.com
DB_PORT=5432
DB_USER=api_user
DB_PASSWORD=your-postgres-password
DB_NAME=postgres_control
DB_SSL=true

# API Configuration
PORT=3000
API_KEY=your-secret-api-key-here

# PostgreSQL Server (for creating new databases)
PG_ADMIN_USER=postgres
PG_ADMIN_PASSWORD=your-postgres-password
```

### Step 3: Run the API

**Development mode (with auto-reload):**
```bash
npm run dev
```

**Production mode:**
```bash
# Build
npm run build

# Run
npm start
```

The API will start on `http://localhost:3000`

---

## API Usage

### Authentication

All API endpoints (except `/health`) require authentication via API key in the header:

```bash
-H "X-API-Key: your-secret-api-key-here"
```

### Endpoints

#### Health Check

```bash
GET /health
```

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2024-01-01T00:00:00.000Z",
  "environment": "development"
}
```

#### Create Database

```bash
POST /api/databases
Content-Type: application/json
X-API-Key: your-secret-api-key-here

{
  "friendlyName": "Customer XYZ Database",
  "ownerEmail": "customer@example.com",
  "maxConnections": 20
}
```

**Response:**
```json
{
  "success": true,
  "message": "Database created successfully",
  "data": {
    "id": "uuid-here",
    "database_name": "tenant_abc123",
    "username": "user_abc123",
    "password": "aB3dEf7GhJk9",
    "connection_string": "postgresql://user_abc123:aB3dEf7GhJk9@db.yourdomain.com:5432/tenant_abc123?sslmode=require",
    "owner_email": "customer@example.com",
    "friendly_name": "Customer XYZ Database",
    "max_connections": 20,
    "status": "active",
    "created_at": "2024-01-01T00:00:00.000Z"
  }
}
```

#### List All Databases

```bash
GET /api/databases
X-API-Key: your-secret-api-key-here
```

**Response:**
```json
{
  "success": true,
  "count": 5,
  "data": [...]
}
```

#### Get Database by ID

```bash
GET /api/databases/:id
X-API-Key: your-secret-api-key-here
```

#### Get Database Statistics

```bash
GET /api/databases/:id/stats
X-API-Key: your-secret-api-key-here
```

**Response:**
```json
{
  "success": true,
  "data": {
    "database_id": "uuid",
    "database_name": "tenant_abc123",
    "size_bytes": 8388608,
    "size_pretty": "8 MB",
    "active_connections": 2,
    "max_connections": 20
  }
}
```

#### Delete Database

```bash
DELETE /api/databases/:id
X-API-Key: your-secret-api-key-here
```

---

## IP Whitelisting

By default, all databases allow connections from **any IP address** (with SSL required). You can restrict access to specific IPs per database.

### Add IP to Whitelist

```bash
POST /api/databases/:id/whitelist
Content-Type: application/json
X-API-Key: your-secret-api-key-here

{
  "ipAddress": "203.0.113.5/32",
  "description": "Office Network"
}
```

**Supported formats:**
- Single IP: `203.0.113.5/32`
- CIDR range: `189.0.0.0/8`
- Subnet: `192.168.1.0/24`

### List IPs for Database

```bash
GET /api/databases/:id/whitelist
X-API-Key: your-secret-api-key-here
```

### Remove IP from Whitelist

```bash
DELETE /api/databases/:id/whitelist/:whitelistId
X-API-Key: your-secret-api-key-here
```

### How IP Whitelisting Works

1. By default, all IPs can connect (with SSL)
2. When you add the first IP to a database's whitelist, **only those IPs** can connect
3. The API automatically updates `pg_hba.conf` on the PostgreSQL server
4. Changes take effect immediately (PostgreSQL config is reloaded)

---

## Management

### Server Management Commands

```bash
# View PostgreSQL status and connections
pg-status

# List all databases
pg-list-databases

# Backup control database
pg-backup-control

# View PostgreSQL logs
tail -f /var/log/postgresql/postgresql-16-main.log

# Restart PostgreSQL
sudo systemctl restart postgresql

# Reload PostgreSQL config (for pg_hba.conf changes)
sudo systemctl reload postgresql
```

### Database Connection

**From terminal:**
```bash
# Connect to a tenant database
PGPASSWORD='password' psql -h db.yourdomain.com -U user_abc123 -d tenant_abc123

# Connect to control database
PGPASSWORD='your-password' psql -h db.yourdomain.com -U api_user -d postgres_control
```

**Connection string format:**
```
postgresql://username:password@host:port/database?sslmode=require
```

### Backup and Restore

**Automated backups:**
- Control database is backed up daily at 2 AM
- Backups stored in `/var/backups/postgresql/`
- Retention: 7 days

**Manual backup:**
```bash
# Backup control database
pg-backup-control

# Backup specific tenant database
sudo -u postgres pg_dump tenant_abc123 | gzip > backup.sql.gz

# Restore
gunzip -c backup.sql.gz | PGPASSWORD='password' psql -h db.yourdomain.com -U user_abc123 -d tenant_abc123
```

---

## Security

### SSL/TLS

- All connections require SSL/TLS encryption
- Certificates from Let's Encrypt
- Auto-renewal configured
- TLSv1.2 minimum

### Authentication

- API: API key-based authentication
- PostgreSQL: SCRAM-SHA-256 password authentication
- Each tenant has isolated credentials

### Network Security

- Default: Open to all IPs (with SSL required)
- Optional: Per-database IP whitelisting
- Firewall: Manage via hardware/cloud firewall

### Password Security

- Generated passwords: 12-16 alphanumeric characters
- Stored hashed in control database (bcrypt)
- Only shown once during creation

### Best Practices

1. **Use strong API keys**: 32+ characters, random
2. **Enable IP whitelisting** for sensitive databases
3. **Rotate credentials** periodically
4. **Monitor logs** regularly
5. **Keep backups** secure and tested
6. **Update PostgreSQL** regularly

---

## Testing Examples

### Create a Test Database

```bash
curl -X POST http://localhost:3000/api/databases \
  -H "X-API-Key: your-secret-api-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "friendlyName": "Test Database",
    "ownerEmail": "test@example.com",
    "maxConnections": 10
  }'
```

### Connect and Create Tables

```bash
# Save the connection details from the response
PGPASSWORD='aB3dEf7GhJk9' psql -h db.yourdomain.com -U user_abc123 -d tenant_abc123

# Inside psql:
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  email VARCHAR(100),
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO users (name, email) VALUES ('John Doe', 'john@example.com');
SELECT * FROM users;
```

### Add IP Whitelist

```bash
curl -X POST http://localhost:3000/api/databases/uuid-here/whitelist \
  -H "X-API-Key: your-secret-api-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "ipAddress": "203.0.113.5/32",
    "description": "My Office IP"
  }'
```

---

## Troubleshooting

### PostgreSQL won't start

```bash
# Check logs
sudo tail -100 /var/log/postgresql/postgresql-16-main.log

# Check service status
sudo systemctl status postgresql@16-main
```

### SSL certificate issues

```bash
# Check certificate
sudo certbot certificates

# Renew manually
sudo certbot renew

# Test renewal
sudo certbot renew --dry-run
```

### Connection refused

1. **Check PostgreSQL is listening on all interfaces:**
   ```bash
   sudo ss -tunlp | grep 5432
   ```
   Should show `0.0.0.0:5432`, NOT `127.0.0.1:5432`

   **Fix if needed:**
   ```bash
   # Edit postgresql.conf
   sudo sed -i "s/^#*listen_addresses *=.*/listen_addresses = '*'/" /etc/postgresql/16/main/postgresql.conf

   # Restart PostgreSQL
   sudo systemctl restart postgresql
   ```

2. Check firewall (ports 5432, 80, 22)
3. Verify pg_hba.conf: `sudo cat /etc/postgresql/16/main/pg_hba.conf`
4. Test SSL: `openssl s_client -connect db.yourdomain.com:5432 -starttls postgres`

### API connection errors

1. Verify `.env` credentials
2. Test control database connection: `PGPASSWORD='pass' psql -h db.yourdomain.com -U api_user -d postgres_control`
3. Check API logs for errors

---

## Architecture

### Components

1. **PostgreSQL Server** (Ubuntu 24.04)
   - PostgreSQL 16 with SSL
   - Control database for metadata
   - Tenant databases (isolated)

2. **REST API** (Node.js/Express)
   - Database provisioning
   - IP whitelist management
   - Statistics and monitoring

3. **Control Database** (postgres_control)
   - `databases` - Tenant database metadata
   - `ip_whitelist` - Per-database IP restrictions
   - `api_keys` - API authentication
   - `audit_logs` - Operation tracking
   - `database_stats` - Usage metrics

### Data Flow

```
Client → API (with API Key)
  ↓
API → Control Database (metadata)
  ↓
API → PostgreSQL Admin (create database)
  ↓
Client ← Connection String
  ↓
Client → Tenant Database (with SSL)
```

---

## Production Deployment

### API Deployment Options

1. **Same server as PostgreSQL** (simple)
2. **Separate server** (recommended for scale)
3. **Serverless** (e.g., Vercel, AWS Lambda)
4. **Container** (Docker, Kubernetes)

### Environment Variables for Production

```env
NODE_ENV=production
DB_HOST=db.yourdomain.com
DB_SSL=true
API_KEY=use-a-very-strong-random-key-here
```

### Process Management

**Using PM2:**
```bash
npm install -g pm2
pm2 start dist/main.js --name postgres-api
pm2 startup
pm2 save
```

**Using systemd:**
Create `/etc/systemd/system/postgres-api.service`

---

## License

MIT

## Support

For issues or questions:
- Check logs: `/var/log/postgresql/`
- Review configuration: `/etc/postgresql/16/main/`
- Test connections with `psql`
- Verify SSL with `openssl s_client`

---

## Credits

Built with:
- PostgreSQL 16
- Node.js & Express
- TypeScript
- Let's Encrypt
- Ubuntu 24.04
