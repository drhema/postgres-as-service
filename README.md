# PostgreSQL Multi-Tenant SaaS Platform

Complete PostgreSQL-as-a-Service platform with REST API for database provisioning, SSL/TLS encryption, and per-database IP whitelisting. Now with **Redis AI Cache** for multi-site deployments!

## Features

### PostgreSQL Database Service
- ✅ PostgreSQL 16 with SSL/TLS (Let's Encrypt)
- ✅ Multi-tenant database isolation
- ✅ REST API for database management
- ✅ Per-database IP whitelisting (optional)
- ✅ Automatic SSL certificate renewal
- ✅ Database statistics and monitoring
- ✅ Audit logging
- ✅ Daily automated backups
- ✅ **PgBouncer connection pooling** (transaction mode)
- ✅ **Shadow databases** for Prisma migrations

### Redis AI Cache (NEW!)
- ✅ Redis 7.x optimized for AI workloads
- ✅ Multi-site support with key prefixes
- ✅ Semantic caching for LLM responses (save 31% on costs)
- ✅ Vector search support (6 parallel workers)
- ✅ Embeddings cache for OpenAI/Anthropic
- ✅ 4GB memory limit, 10K connections
- ✅ Enhanced monitoring and analytics

## Table of Contents

1. [PostgreSQL Installation](#server-installation)
2. [Redis Installation](#redis-installation-new)
3. [PgBouncer Connection Pooling](#pgbouncer-connection-pooling)
4. [Connection Strings (Neon-style)](#connection-strings-neon-style)
5. [API Setup](#api-setup)
6. [API Usage](#api-usage)
7. [IP Whitelisting](#ip-whitelisting)
8. [Management](#management)
9. [Security](#security)

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

## Redis Installation (NEW!)

📖 **See [QUICK-START.md](QUICK-START.md) for the fastest way to get started!**

### Quick Install

One-command installation on your server:

```bash
curl -fsSL https://raw.githubusercontent.com/drhema/postgres-as-service/refs/heads/main/redis.sh | sudo bash
```

**Or download and review first:**

```bash
# Download the script
curl -O https://raw.githubusercontent.com/drhema/postgres-as-service/refs/heads/main/redis.sh

# Review it
cat redis.sh

# Make executable
chmod +x redis.sh

# Run it
sudo ./redis.sh
```

### What Gets Installed

- **Redis 7.x** with AI optimizations
- **4GB memory** (40% of RAM, max)
- **16 databases** for site isolation
- **6 search workers** for vector/AI queries
- **Multi-site support** via key prefixes
- **Enhanced monitoring** script

### Post-Installation

1. **Save your connection URL:**
   ```
   redis://:YOUR_PASSWORD@YOUR_SERVER_IP:6379
   ```

2. **Configure firewall (CRITICAL!):**
   ```bash
   sudo ufw allow from YOUR_APP_SERVER_IP to any port 6379
   sudo ufw deny 6379
   sudo ufw enable
   ```

3. **Test connection:**
   ```bash
   redis-cli -h YOUR_SERVER_IP -p 6379 -a YOUR_PASSWORD ping
   # Should return: PONG
   ```

### Redis Guides

Comprehensive documentation included:

| Guide | Description |
|---|---|
| [REDIS-INSTALLATION.md](REDIS-INSTALLATION.md) | Detailed installation & troubleshooting |
| [REDIS-SETUP-SUMMARY.md](REDIS-SETUP-SUMMARY.md) | Quick reference guide |
| [MULTI-SITE-REDIS-GUIDE.md](MULTI-SITE-REDIS-GUIDE.md) | Multi-site implementation with code examples |
| [AI-CACHE-IMPLEMENTATION-GUIDE.md](AI-CACHE-IMPLEMENTATION-GUIDE.md) | AI caching, RAG, vector search, semantic cache |

### Use Cases

**1. Semantic Caching (Save 31% LLM costs):**
```javascript
const cache = new SemanticCache({
  redis_url: 'redis://:PASSWORD@HOST:6379',
  ttl: 3600
});

// Check cache before calling OpenAI
const cached = await cache.check(prompt);
```

**2. Multi-Site Product Cache:**
```javascript
// All sites share one Redis URL
await redis.setEx(
  `site:${siteId}:products:${id}`,
  3600,
  JSON.stringify(product)
);
```

**3. Vector Search for RAG:**
```python
# Retrieve relevant context for LLM
results = index.query(
  VectorQuery(vector=query_embedding, num_results=3)
)
```

**4. Chat Session History:**
```javascript
await redis.rPush(
  `site:${siteId}:chat:${sessionId}`,
  JSON.stringify(message)
);
```

### Cost Savings

**With 80% cache hit rate:**
- 10K LLM requests/day @ $0.03 each
- Without cache: **$300/day**
- With cache: **$60/day**
- **Savings: $87,600/year**

See [AI-CACHE-IMPLEMENTATION-GUIDE.md](AI-CACHE-IMPLEMENTATION-GUIDE.md) for complete examples.

---

## PgBouncer Connection Pooling

### What is PgBouncer?

PgBouncer is a lightweight connection pooler for PostgreSQL that dramatically improves performance for applications with many concurrent connections. It sits between your application and PostgreSQL, multiplexing connections.

**Benefits:**
- ⚡ **Handle 1000s of client connections** with only 25-50 actual PostgreSQL connections
- 🚀 **Transaction pooling mode** - One PostgreSQL connection per transaction (not per session)
- 💰 **Reduce server load** - Lower memory usage and CPU overhead
- 🔄 **Automatic connection reuse** - No connection overhead for each query
- 🌐 **Perfect for web apps** and serverless functions (Lambda, Vercel, etc.)

### Installation

PgBouncer is **automatically installed** when you run the installation script:

```bash
sudo ./postgres.sh
# OR
sudo ./postgres-dns.sh
```

The script automatically:
1. Installs PgBouncer package
2. Configures transaction pooling mode
3. Sets up authentication
4. Creates systemd service
5. Opens port 6432 in firewall

### Configuration

PgBouncer is **disabled by default**. To enable it in your API:

**1. Update your `.env` file:**

```env
# Enable PgBouncer connection pooling
DB_PGBOUNCER_ENABLED=true
DB_PGBOUNCER_PORT=6432
```

**2. Restart your API:**

```bash
npm run dev
# OR
pm2 restart postgres-api
```

### Connection Strings

**With PgBouncer enabled (port 6432):**
```
postgresql://username:password@db.yourdomain.com:6432/database?sslmode=require
```

**Direct PostgreSQL (port 5432):**
```
postgresql://username:password@db.yourdomain.com:5432/database?sslmode=require
```

### Architecture

```
┌─────────────────┐
│ Your Application│  (100 concurrent connections)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    PgBouncer    │  Port 6432 (Transaction pooling)
│  (Multiplexer)  │  Max 1000 clients → 25 PostgreSQL connections
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   PostgreSQL    │  Port 5432 (Direct connection)
│  (Database)     │  Only 25 connections needed instead of 100
└─────────────────┘
```

### Performance Comparison

| Scenario | Without PgBouncer | With PgBouncer | Improvement |
|----------|-------------------|----------------|-------------|
| 100 concurrent API requests | 100 PostgreSQL connections | 25 connections | **75% reduction** |
| Memory usage (per connection) | ~10MB × 100 = 1GB | ~10MB × 25 = 250MB | **75% less RAM** |
| Connection overhead | High (new connection per request) | Low (reused connections) | **10x faster** |
| Serverless functions | Connection timeout issues | Seamless operation | **Reliable** |

### When to Use PgBouncer

**✅ Recommended for:**
- Web applications with many concurrent users
- Serverless deployments (AWS Lambda, Vercel, Netlify)
- Microservices architecture
- API services with burst traffic
- Applications with short-lived connections

**❌ Not needed for:**
- Single long-running application
- Background workers with persistent connections
- Applications already using application-level pooling effectively

### Pooling Modes

Our installation uses **transaction mode** (recommended for web apps):

| Mode | Connection Released | Use Case |
|------|---------------------|----------|
| **Transaction** | After each transaction | Web apps, APIs, serverless ✅ |
| Session | When client disconnects | Legacy apps requiring session state |
| Statement | After each statement | Rarely used |

### Management Commands

```bash
# Check PgBouncer status
sudo systemctl status pgbouncer

# Restart PgBouncer
sudo systemctl restart pgbouncer

# View PgBouncer logs
sudo journalctl -u pgbouncer -f

# Connect to PgBouncer admin console
psql -h localhost -p 6432 -U postgres -d pgbouncer

# Inside pgbouncer console:
SHOW POOLS;        # View connection pools
SHOW CLIENTS;      # View client connections
SHOW SERVERS;      # View server connections
SHOW STATS;        # View statistics
RELOAD;            # Reload configuration
```

### Configuration File

Location: `/etc/pgbouncer/pgbouncer.ini`

**Key settings:**
```ini
[pgbouncer]
pool_mode = transaction           # Transaction pooling
max_client_conn = 1000            # Maximum client connections
default_pool_size = 25            # PostgreSQL connections per database
listen_addr = 0.0.0.0             # Listen on all interfaces
listen_port = 6432                # PgBouncer port
auth_type = scram-sha-256         # Authentication method
server_tls_sslmode = require      # Require SSL to PostgreSQL
```

### Troubleshooting

**Connection refused on port 6432:**
```bash
# Check if PgBouncer is running
sudo systemctl status pgbouncer

# Check if port is listening
sudo ss -tunlp | grep 6432

# Check firewall
sudo ufw status | grep 6432
```

**Authentication failed:**
```bash
# Verify credentials in /etc/pgbouncer/userlist.txt
sudo cat /etc/pgbouncer/userlist.txt

# Restart PgBouncer after changes
sudo systemctl restart pgbouncer
```

**Performance not improving:**
```bash
# Ensure DB_PGBOUNCER_ENABLED=true in .env
# Check application is using port 6432
# Monitor pool usage: SHOW POOLS; in pgbouncer console
```

### Monitoring

**Check pool statistics:**
```bash
psql -h localhost -p 6432 -U postgres -d pgbouncer -c "SHOW STATS;"
```

**Monitor in real-time:**
```bash
watch -n 2 'psql -h localhost -p 6432 -U postgres -d pgbouncer -c "SHOW POOLS;"'
```

**Example output:**
```
 database        | user     | cl_active | cl_waiting | sv_active | sv_idle | sv_used
-----------------+----------+-----------+------------+-----------+---------+---------
 tenant_abc123   | user_abc | 5         | 0          | 2         | 3       | 5
 postgres_control| api_user | 2         | 0          | 1         | 1       | 2
```

- `cl_active`: Active client connections
- `sv_active`: Active PostgreSQL connections
- `sv_idle`: Idle PostgreSQL connections ready for reuse

---

## Connection Strings (Neon-style)

### Overview

Every database you create comes with **4 connection string variants** - all pointing to the same database, just with different parameters. This is the same approach Neon uses.

**Connection String Types:**

1. **Direct Connection** (`connection_string`)
   - Port 5432 (direct PostgreSQL)
   - Use for: Admin operations, migrations, pg_dump

2. **Pooled Connection** (`connection_string_pooled`)
   - Port 6432 + `?pgbouncer=true` parameter
   - Use for: Web applications, API servers, serverless

3. **Shadow Database** (`shadow_database_url`)
   - Port 5432 + `?schema=public` parameter
   - Use for: Prisma shadow database (migrations)

4. **Shadow + Pooled** (`shadow_database_url_pooled`)
   - Port 6432 + `?schema=public&pgbouncer=true`
   - Use for: Prisma migrations with connection pooling

**Key Concept:** Unlike traditional approaches that create separate shadow databases, we use the **same database** with URL parameters - exactly like Neon!

### Example Response

When you create a database, you receive all 4 connection strings immediately:

```bash
POST /api/databases
X-API-Key: your-secret-api-key-here

{
  "friendlyName": "My App Database",
  "ownerEmail": "user@example.com",
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
    "owner_email": "user@example.com",
    "friendly_name": "My App Database",
    "max_connections": 20,
    "status": "active",
    "created_at": "2024-01-01T00:00:00.000Z",

    "connection_string": "postgresql://user_abc123:aB3dEf7GhJk9@db.yourdomain.com:5432/tenant_abc123?sslmode=require",

    "connection_string_pooled": "postgresql://user_abc123:aB3dEf7GhJk9@db.yourdomain.com:6432/tenant_abc123?sslmode=require&pgbouncer=true",

    "shadow_database_url": "postgresql://user_abc123:aB3dEf7GhJk9@db.yourdomain.com:5432/tenant_abc123?sslmode=require&schema=public",

    "shadow_database_url_pooled": "postgresql://user_abc123:aB3dEf7GhJk9@db.yourdomain.com:6432/tenant_abc123?sslmode=require&schema=public&pgbouncer=true"
  }
}
```

### Get Connection Strings

If you need to retrieve connection strings later (password masked):

```bash
GET /api/databases/:id/connection-strings
X-API-Key: your-secret-api-key-here
```

**Response:**
```json
{
  "success": true,
  "data": {
    "database_id": "uuid-here",
    "database_name": "tenant_abc123",
    "username": "user_abc123",
    "connection_string": "postgresql://user_abc123:***@db.yourdomain.com:5432/tenant_abc123?sslmode=require",
    "connection_string_pooled": "postgresql://user_abc123:***@db.yourdomain.com:6432/tenant_abc123?sslmode=require&pgbouncer=true",
    "shadow_database_url": "postgresql://user_abc123:***@db.yourdomain.com:5432/tenant_abc123?sslmode=require&schema=public",
    "shadow_database_url_pooled": "postgresql://user_abc123:***@db.yourdomain.com:6432/tenant_abc123?sslmode=require&schema=public&pgbouncer=true",
    "note": "All URLs use the same database. Use ?pgbouncer=true for connection pooling and ?schema=public for Prisma shadow database."
  }
}
```

### Prisma Integration

**Option 1: Direct Connection (for migrations)**

```env
# Main database
DATABASE_URL="postgresql://user_abc123:password@db.yourdomain.com:5432/tenant_abc123?sslmode=require"

# Shadow database (same database, different parameter)
SHADOW_DATABASE_URL="postgresql://user_abc123:password@db.yourdomain.com:5432/tenant_abc123?sslmode=require&schema=public"
```

**Option 2: With PgBouncer (production)**

```env
# Main database (pooled)
DATABASE_URL="postgresql://user_abc123:password@db.yourdomain.com:6432/tenant_abc123?sslmode=require&pgbouncer=true"

# Shadow database (pooled)
SHADOW_DATABASE_URL="postgresql://user_abc123:password@db.yourdomain.com:6432/tenant_abc123?sslmode=require&schema=public&pgbouncer=true"
```

**Your `prisma/schema.prisma`:**

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider          = "postgresql"
  url               = env("DATABASE_URL")
  shadowDatabaseUrl = env("SHADOW_DATABASE_URL")  // Same DB, just different URL parameter!
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String?
  createdAt DateTime @default(now())
}
```

**Run migrations:**

```bash
npx prisma migrate dev --name init

# Prisma will:
# 1. Test migrations on the same database (using schema=public parameter)
# 2. Apply to your main database
# 3. Generate Prisma Client
```

### Complete Workflow Example

**Step 1: Create a database**

```bash
curl -X POST http://localhost:3000/api/databases \
  -H "X-API-Key: your-secret-api-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "friendlyName": "Customer Database",
    "ownerEmail": "customer@example.com",
    "maxConnections": 20
  }'
```

You'll receive all 4 connection strings in the response!

**Step 2: Configure your app**

Create `.env`:
```env
# For production (use pooled)
DATABASE_URL="postgresql://user_abc123:pass@db.yourdomain.com:6432/tenant_abc123?sslmode=require&pgbouncer=true"

# For Prisma migrations (same DB, different parameter)
SHADOW_DATABASE_URL="postgresql://user_abc123:pass@db.yourdomain.com:6432/tenant_abc123?sslmode=require&schema=public&pgbouncer=true"
```

**Step 3: Run Prisma migrations**

```bash
npx prisma migrate dev --name init
```

That's it! No separate shadow database to manage.

### Key Differences from Traditional Approach

| Traditional (Complex) | Neon-style (Simple) |
|----------------------|---------------------|
| 2 databases (`tenant_abc123` + `tenant_abc123_shadow`) | 1 database (`tenant_abc123`) |
| 2 users (`user_abc123` + `user_abc123_shadow`) | 1 user (`user_abc123`) |
| 2 passwords to manage | 1 password |
| Shadow DB must be synced | No sync needed |
| Consumes 2x storage | Same storage |
| Separate CREATE/DELETE operations | Just use URL parameters |

### Why This Works

PostgreSQL and Prisma don't actually need separate physical databases for shadow functionality. The `?schema=public` parameter is enough for Prisma to understand it's working with a shadow context. Neon figured this out and we've implemented the same approach!

### Connection String Parameters

| Parameter | Purpose | Example |
|-----------|---------|---------|
| `?sslmode=require` | Enable SSL/TLS | Always included |
| `?pgbouncer=true` | Route through PgBouncer (port 6432) | For apps/APIs |
| `?schema=public` | Indicate shadow database context | For Prisma migrations |
| Combined | Both pooling + shadow | `?sslmode=require&schema=public&pgbouncer=true` |

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

#### Get Connection Strings

Get all connection string variants for a database (direct, pooled, shadow):

```bash
GET /api/databases/:id/connection-strings
X-API-Key: your-secret-api-key-here
```

**Response:**
```json
{
  "success": true,
  "data": {
    "database_id": "uuid",
    "database_name": "tenant_abc123",
    "username": "user_abc123",
    "connection_string": "postgresql://user_abc123:***@db.yourdomain.com:5432/tenant_abc123?sslmode=require",
    "connection_string_pooled": "postgresql://user_abc123:***@db.yourdomain.com:6432/tenant_abc123?sslmode=require&pgbouncer=true",
    "shadow_database_url": "postgresql://user_abc123:***@db.yourdomain.com:5432/tenant_abc123?sslmode=require&schema=public",
    "shadow_database_url_pooled": "postgresql://user_abc123:***@db.yourdomain.com:6432/tenant_abc123?sslmode=require&schema=public&pgbouncer=true",
    "note": "All URLs use the same database. Use ?pgbouncer=true for connection pooling and ?schema=public for Prisma shadow database."
  }
}
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

**PostgreSQL Commands:**
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

**PgBouncer Commands:**
```bash
# Check PgBouncer status
sudo systemctl status pgbouncer

# Restart PgBouncer
sudo systemctl restart pgbouncer

# View PgBouncer logs
sudo journalctl -u pgbouncer -f

# Connect to PgBouncer admin console
psql -h localhost -p 6432 -U postgres -d pgbouncer

# View connection pools
psql -h localhost -p 6432 -U postgres -d pgbouncer -c "SHOW POOLS;"

# View statistics
psql -h localhost -p 6432 -U postgres -d pgbouncer -c "SHOW STATS;"
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
   - Tenant databases (isolated, supports Prisma shadow via URL parameters)
   - PgBouncer connection pooler (port 6432)

2. **REST API** (Node.js/Express)
   - Database provisioning
   - Connection string generation (4 variants per database)
   - IP whitelist management
   - Statistics and monitoring

3. **Control Database** (postgres_control)
   - `databases` - Tenant database metadata
   - `ip_whitelist` - Per-database IP restrictions
   - `api_keys` - API authentication
   - `audit_logs` - Operation tracking
   - `database_stats` - Usage metrics

### Data Flow

**Database Creation Flow:**
```
Client → API (with API Key)
  ↓
API → Control Database (metadata)
  ↓
API → PostgreSQL Admin (create database + user)
  ↓
Client ← Connection String
  ↓
Client → Tenant Database (with SSL)
```

**Connection Flow with PgBouncer:**
```
Client Application (100 connections)
  ↓
PgBouncer Port 6432 (Transaction pooling)
  ↓
PostgreSQL (Only 25 actual connections)
  ↓
Tenant Database
```

**Prisma Migration Flow (Neon-style):**
```
Developer → Prisma Migrate Dev
  ↓
Prisma → Same Database with ?schema=public (test migration)
  ↓
Prisma → Same Database (apply migration)
  ↓
Application ← Updated Schema

Note: Both URLs point to the same physical database!
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

# Enable PgBouncer for production (recommended)
DB_PGBOUNCER_ENABLED=true
DB_PGBOUNCER_PORT=6432
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
