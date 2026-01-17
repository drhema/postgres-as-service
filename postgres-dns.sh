#!/usr/bin/env bash
#
# PostgreSQL 16 Server Setup for Multi-Tenant SaaS
# DNS Challenge Edition - Compatible with Nginx Proxy Manager
# Complete installation with SSL via Cloudflare DNS, control database, and management utilities
# Run on Ubuntu 24.04 as root
#

set -euo pipefail

# Colors for output
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

# Logging functions
log_info() {
  echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
  fi
}

# Display banner
show_banner() {
  echo -e "${GREEN}"
  cat <<'BANNER'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     PostgreSQL 16 Multi-Tenant SaaS Server Setup              ║
║          DNS Challenge Edition - Cloudflare DNS               ║
║         Compatible with Nginx Proxy Manager                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
BANNER
  echo -e "${NC}"
}

# Prompt for configuration
get_configuration() {
  echo -e "${CYAN}Please provide the following information:${NC}\n"

  read -p "Enter your domain for SSL (e.g., db.yourdomain.com): " DOMAIN
  while [[ -z "$DOMAIN" ]]; do
    log_error "Domain cannot be empty"
    read -p "Enter your domain for SSL: " DOMAIN
  done

  read -p "Enter email for Let's Encrypt notifications: " EMAIL
  while [[ -z "$EMAIL" ]]; do
    log_error "Email cannot be empty"
    read -p "Enter email for Let's Encrypt: " EMAIL
  done

  echo ""
  echo -e "${CYAN}Choose SSL certificate method:${NC}"
  echo "  1) Cloudflare DNS API (Recommended - Automated)"
  echo "  2) Manual DNS TXT Record (No API token needed)"
  echo ""
  read -p "Select option [1-2]: " SSL_METHOD

  while [[ ! "$SSL_METHOD" =~ ^[1-2]$ ]]; do
    log_error "Please select 1 or 2"
    read -p "Select option [1-2]: " SSL_METHOD
  done

  if [[ "$SSL_METHOD" == "1" ]]; then
    echo ""
    echo -e "${YELLOW}You need a Cloudflare API Token with DNS edit permissions.${NC}"
    echo -e "${YELLOW}Create one at: https://dash.cloudflare.com/profile/api-tokens${NC}"
    echo -e "${YELLOW}Use the 'Edit zone DNS' template${NC}"
    echo ""
    read -p "Enter your Cloudflare API Token: " CF_API_TOKEN
    while [[ -z "$CF_API_TOKEN" ]]; do
      log_error "API Token cannot be empty"
      read -p "Enter your Cloudflare API Token: " CF_API_TOKEN
    done
  fi

  read -sp "Enter PostgreSQL admin password (min 12 chars): " POSTGRES_ADMIN_PASSWORD
  echo
  while [[ ${#POSTGRES_ADMIN_PASSWORD} -lt 12 ]]; do
    log_error "Password must be at least 12 characters"
    read -sp "Enter PostgreSQL admin password: " POSTGRES_ADMIN_PASSWORD
    echo
  done

  read -sp "Confirm PostgreSQL admin password: " POSTGRES_ADMIN_PASSWORD_CONFIRM
  echo
  while [[ "$POSTGRES_ADMIN_PASSWORD" != "$POSTGRES_ADMIN_PASSWORD_CONFIRM" ]]; do
    log_error "Passwords do not match"
    read -sp "Enter PostgreSQL admin password: " POSTGRES_ADMIN_PASSWORD
    echo
    read -sp "Confirm password: " POSTGRES_ADMIN_PASSWORD_CONFIRM
    echo
  done

  echo ""
  log_info "Configuration summary:"
  echo "  Domain: $DOMAIN"
  echo "  Email: $EMAIL"
  echo "  SSL Method: $([ "$SSL_METHOD" == "1" ] && echo "Cloudflare DNS API" || echo "Manual DNS")"
  echo "  Password: ********"
  echo ""

  read -p "Continue with installation? [y/N]: " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_error "Installation cancelled"
    exit 1
  fi
}

# Update system packages
update_system() {
  log_info "Updating system packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get upgrade -y -qq
  log_success "System updated"
}

# Install PostgreSQL 16
install_postgresql() {
  log_info "Installing PostgreSQL 16..."

  # Add PostgreSQL APT repository
  apt-get install -y -qq postgresql-common
  /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y

  # Install PostgreSQL 16, contrib packages, and extensions
  apt-get install -y \
    postgresql-16 \
    postgresql-contrib-16 \
    postgresql-client-16 \
    postgresql-16-pgvector \
    postgresql-16-postgis-3

  log_success "PostgreSQL 16 and extensions installed"
}

# Install SSL and other tools
install_dependencies() {
  log_info "Installing dependencies..."

  apt-get install -y -qq \
    certbot \
    python3-certbot-dns-cloudflare \
    curl \
    htop \
    net-tools \
    openssl \
    pgbouncer

  log_success "Dependencies installed (including Cloudflare DNS plugin and PgBouncer)"
}

# Obtain SSL certificate using DNS challenge
obtain_ssl_certificate() {
  if [[ "$SSL_METHOD" == "1" ]]; then
    obtain_ssl_cloudflare_api
  else
    obtain_ssl_manual_dns
  fi
}

# Cloudflare API method
obtain_ssl_cloudflare_api() {
  log_info "Obtaining SSL certificate using Cloudflare DNS API for $DOMAIN..."

  # Create Cloudflare credentials file
  mkdir -p /root/.secrets
  cat > /root/.secrets/cloudflare.ini <<EOF
# Cloudflare API token
dns_cloudflare_api_token = $CF_API_TOKEN
EOF
  chmod 600 /root/.secrets/cloudflare.ini

  # Obtain certificate using DNS challenge
  certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
    --dns-cloudflare-propagation-seconds 60 \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --domain "$DOMAIN"

  if [[ $? -ne 0 ]]; then
    log_error "Failed to obtain SSL certificate via Cloudflare DNS"
    log_error "Please check:"
    log_error "  1. Your API token has DNS edit permissions"
    log_error "  2. The domain $DOMAIN is managed by Cloudflare"
    log_error "  3. The API token is for the correct Cloudflare account"
    exit 1
  fi

  log_success "SSL certificate obtained for $DOMAIN via Cloudflare DNS"
}

# Manual DNS method
obtain_ssl_manual_dns() {
  log_info "Obtaining SSL certificate using Manual DNS challenge for $DOMAIN..."

  echo ""
  log_warn "========================================================================="
  log_warn "                    MANUAL DNS CHALLENGE MODE"
  log_warn "========================================================================="
  log_warn ""
  log_warn "Certbot will now show you a TXT record that you need to add to your DNS."
  log_warn ""
  log_warn "Steps:"
  log_warn "  1. Certbot will display: _acme-challenge.${DOMAIN}"
  log_warn "  2. Copy the TXT record value shown"
  log_warn "  3. Go to your DNS provider (Cloudflare, etc.)"
  log_warn "  4. Add a new TXT record:"
  log_warn "       Name:  _acme-challenge"
  log_warn "       Type:  TXT"
  log_warn "       Value: (the value certbot shows you)"
  log_warn "  5. Wait 1-2 minutes for DNS propagation"
  log_warn "  6. Press Enter when certbot prompts you"
  log_warn ""
  log_warn "========================================================================="
  echo ""
  read -p "Press Enter when you're ready to start..."

  # Run certbot in interactive mode to show the TXT record
  certbot certonly \
    --manual \
    --preferred-challenges dns \
    --agree-tos \
    --email "$EMAIL" \
    --domain "$DOMAIN"

  if [[ $? -ne 0 ]]; then
    log_error "Failed to obtain SSL certificate"
    log_error "Please ensure you added the DNS TXT record correctly"
    log_error ""
    log_error "Common issues:"
    log_error "  - TXT record not added correctly"
    log_error "  - DNS not propagated (wait 2-5 minutes)"
    log_error "  - Wrong DNS provider/zone"
    echo ""
    log_info "You can retry by running: certbot certonly --manual --preferred-challenges dns -d $DOMAIN"
    exit 1
  fi

  log_success "SSL certificate obtained for $DOMAIN via Manual DNS"
}

# Configure PostgreSQL SSL
configure_postgresql_ssl() {
  log_info "Configuring PostgreSQL SSL certificates..."

  # Create SSL directory
  mkdir -p /etc/postgresql/16/main/ssl

  # Copy certificates
  cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/postgresql/16/main/ssl/server.crt
  cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /etc/postgresql/16/main/ssl/server.key

  # Set proper ownership and permissions
  chown postgres:postgres /etc/postgresql/16/main/ssl/server.crt
  chown postgres:postgres /etc/postgresql/16/main/ssl/server.key
  chmod 600 /etc/postgresql/16/main/ssl/server.key
  chmod 644 /etc/postgresql/16/main/ssl/server.crt

  log_success "SSL certificates configured for PostgreSQL"
}

# Configure PostgreSQL
configure_postgresql() {
  log_info "Configuring PostgreSQL..."

  # Backup original configs
  cp /etc/postgresql/16/main/postgresql.conf /etc/postgresql/16/main/postgresql.conf.backup
  cp /etc/postgresql/16/main/pg_hba.conf /etc/postgresql/16/main/pg_hba.conf.backup

  # Get server memory for tuning
  TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))

  # Calculate shared_buffers (25% of RAM, max 8GB)
  SHARED_BUFFERS_GB=$((TOTAL_MEM_GB / 4))
  if [ $SHARED_BUFFERS_GB -gt 8 ]; then
    SHARED_BUFFERS_GB=8
  fi
  if [ $SHARED_BUFFERS_GB -lt 1 ]; then
    SHARED_BUFFERS_GB=1
  fi

  # Calculate effective_cache_size (75% of RAM)
  EFFECTIVE_CACHE_GB=$((TOTAL_MEM_GB * 3 / 4))
  if [ $EFFECTIVE_CACHE_GB -lt 1 ]; then
    EFFECTIVE_CACHE_GB=1
  fi

  # CRITICAL FIX: Replace listen_addresses instead of just appending
  # This ensures PostgreSQL listens on all interfaces, not just localhost
  sed -i "s/^#*listen_addresses *=.*/listen_addresses = '*'/" /etc/postgresql/16/main/postgresql.conf

  # Update postgresql.conf with additional settings
  cat >> /etc/postgresql/16/main/postgresql.conf <<EOF

# ===================================================================
# Custom Configuration for Multi-Tenant PostgreSQL SaaS
# Auto-configured based on server specs
# ===================================================================

# Connection Settings
# listen_addresses is already set above via sed command
port = 5432
max_connections = 500
superuser_reserved_connections = 10

# Memory Settings (tuned for ${TOTAL_MEM_GB}GB RAM)
shared_buffers = ${SHARED_BUFFERS_GB}GB
effective_cache_size = ${EFFECTIVE_CACHE_GB}GB
work_mem = 16MB
maintenance_work_mem = 512MB
wal_buffers = 16MB

# Checkpoint Settings
checkpoint_completion_target = 0.9
checkpoint_timeout = 15min
max_wal_size = 2GB
min_wal_size = 1GB

# Query Planner
random_page_cost = 1.1
effective_io_concurrency = 200

# SSL Configuration
ssl = on
ssl_cert_file = '/etc/postgresql/16/main/ssl/server.crt'
ssl_key_file = '/etc/postgresql/16/main/ssl/server.key'
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'
ssl_prefer_server_ciphers = on
ssl_min_protocol_version = 'TLSv1.2'

# Logging
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_truncate_on_rotation = off
log_rotation_age = 1d
log_rotation_size = 100MB
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_timezone = 'UTC'
log_statement = 'ddl'
log_duration = off
log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0

# Performance Extensions
shared_preload_libraries = 'pg_stat_statements'

# Statistics
track_activities = on
track_counts = on
track_io_timing = on
track_functions = all
track_activity_query_size = 2048

# Autovacuum
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = 10s
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_scale_factor = 0.02

# Locale
datestyle = 'iso, mdy'
timezone = 'UTC'
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'
default_text_search_config = 'pg_catalog.english'
EOF

  # Configure pg_hba.conf
  cat > /etc/postgresql/16/main/pg_hba.conf <<'EOF'
# PostgreSQL Client Authentication Configuration File
# This file controls: which hosts are allowed to connect, how clients
# are authenticated, which PostgreSQL user names they can use, which
# databases they can access.
#
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# ===================================================================
# Local connections (Unix socket)
# ===================================================================
local   all             postgres                                peer
local   all             all                                     scram-sha-256

# ===================================================================
# Localhost connections (127.0.0.1)
# ===================================================================
host    all             postgres        127.0.0.1/32            scram-sha-256
host    all             all             127.0.0.1/32            scram-sha-256

# IPv6 localhost
host    all             postgres        ::1/128                 scram-sha-256
host    all             all             ::1/128                 scram-sha-256

# ===================================================================
# Allow replication connections from localhost
# ===================================================================
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            scram-sha-256
host    replication     all             ::1/128                 scram-sha-256

# ===================================================================
# Docker Network Access (non-SSL for internal containers)
# These ranges cover Docker bridge networks (172.16.0.0/12)
# and common private networks used by Docker Compose
# ===================================================================
host    all             all             172.16.0.0/12           scram-sha-256
host    all             all             192.168.0.0/16          scram-sha-256
host    all             all             10.0.0.0/8              scram-sha-256

# ===================================================================
# GLOBAL ACCESS - Allow all IPs (with SSL required)
# Default rule: Allow any IP to connect to any database
# The API will manage per-database IP restrictions below
# ===================================================================
hostssl all             all             0.0.0.0/0               scram-sha-256
hostssl all             all             ::/0                    scram-sha-256

# ===================================================================
# API MANAGED SECTION - Per-Database IP Whitelisting
# DO NOT EDIT BELOW THIS LINE - MANAGED BY API
#
# When IP whitelisting is enabled for a database, the API will:
# 1. Add specific rules here for allowed IPs
# 2. Add a REJECT rule at the end to block all other IPs
#
# Example format:
# hostssl tenant_abc123  user_abc123   203.0.113.5/32    scram-sha-256
# hostssl tenant_abc123  user_abc123   0.0.0.0/0         reject
# ===================================================================
### API_MANAGED_SECTION_START ###

### API_MANAGED_SECTION_END ###
EOF

  log_success "PostgreSQL configured"
}

# Start PostgreSQL
start_postgresql() {
  log_info "Starting PostgreSQL..."

  systemctl enable postgresql

  # Restart to apply configuration changes (especially listen_addresses)
  systemctl restart postgresql

  # Wait for PostgreSQL to be ready
  sleep 3

  if systemctl is-active --quiet postgresql; then
    log_success "PostgreSQL started successfully"
  else
    log_error "Failed to start PostgreSQL"
    systemctl status postgresql
    exit 1
  fi
}

# Set PostgreSQL admin password
set_postgres_password() {
  log_info "Setting PostgreSQL admin password..."

  sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$POSTGRES_ADMIN_PASSWORD';"

  log_success "PostgreSQL admin password set"
}

# Configure PgBouncer
configure_pgbouncer() {
  log_info "Configuring PgBouncer connection pooler..."

  # Create PgBouncer directories
  mkdir -p /etc/pgbouncer
  mkdir -p /var/log/pgbouncer
  mkdir -p /var/run/pgbouncer
  chown -R postgres:postgres /var/log/pgbouncer
  chown -R postgres:postgres /var/run/pgbouncer

  # Note: With auth_query, passwords are fetched from PostgreSQL
  # We still add admin users to userlist.txt for initial access
  # Using SCRAM-SHA-256, passwords will be verified via auth_query

  # Create pgbouncer.ini configuration
  cat > /etc/pgbouncer/pgbouncer.ini <<'PGBOUNCER_INI'
[databases]
postgres_control = host=127.0.0.1 port=5432 dbname=postgres_control
postgres = host=127.0.0.1 port=5432 dbname=postgres
* = host=127.0.0.1 port=5432

[pgbouncer]
; Connection pooling mode
; session = RECOMMENDED for Prisma ORM and modern ORMs (connection persists for entire client session)
; transaction = Legacy mode (1 connection per transaction) - causes P1017 errors with Prisma
pool_mode = session

; Maximum client connections
max_client_conn = 1000

; Connection pool settings per database
; Session mode uses more connections, so adjust pool sizes accordingly
default_pool_size = 50
min_pool_size = 10
reserve_pool_size = 10
reserve_pool_timeout = 5

; Global limits
max_db_connections = 200
max_user_connections = 200

; Connection lifetime
; Increased timeouts for session mode stability
server_lifetime = 7200
server_idle_timeout = 1800

; Network settings
listen_addr = 0.0.0.0
listen_port = 6432

; Logging
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /var/run/pgbouncer/pgbouncer.pid
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1

; Authentication
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
auth_user = postgres
auth_query = SELECT usename, passwd FROM pg_shadow WHERE usename=$1

; Admin console
admin_users = postgres
stats_users = postgres, api_user

; TLS/SSL (optional - can enable later)
;client_tls_sslmode = prefer
;client_tls_cert_file = /etc/postgresql/16/main/ssl/server.crt
;client_tls_key_file = /etc/postgresql/16/main/ssl/server.key

; Performance tuning
max_packet_size = 4096
pkt_buf = 4096
sbuf_loopcnt = 5
PGBOUNCER_INI

  # Create empty userlist.txt for now (will be populated after api_user is created)
  touch /etc/pgbouncer/userlist.txt

  # Set proper permissions
  chown -R postgres:postgres /etc/pgbouncer
  chmod 640 /etc/pgbouncer/pgbouncer.ini
  chmod 600 /etc/pgbouncer/userlist.txt

  log_success "PgBouncer configuration created (userlist.txt will be populated after users are created)"
}

# Setup PgBouncer authentication (call this AFTER users are created)
setup_pgbouncer_auth() {
  log_info "Setting up PgBouncer authentication with SCRAM-SHA-256..."

  # With auth_query and SCRAM-SHA-256, we need plaintext passwords in userlist.txt
  # PgBouncer will use these to authenticate to PostgreSQL when running auth_query
  # Tenant users will be authenticated via auth_query (fetching from pg_shadow)

  # Create userlist.txt with plaintext passwords for admin users
  cat > /etc/pgbouncer/userlist.txt <<EOF
"postgres" "${POSTGRES_ADMIN_PASSWORD}"
"api_user" "${POSTGRES_ADMIN_PASSWORD}"
EOF

  chmod 600 /etc/pgbouncer/userlist.txt
  chown postgres:postgres /etc/pgbouncer/userlist.txt

  log_success "PgBouncer authentication configured with SCRAM-SHA-256"
}

# Start PgBouncer service
start_pgbouncer() {
  log_info "Starting PgBouncer service..."

  # Create systemd tmpfiles.d configuration for runtime directory
  # This ensures /var/run/pgbouncer is created on boot
  cat > /etc/tmpfiles.d/pgbouncer.conf <<'TMPFILES'
d /var/run/pgbouncer 0755 postgres postgres -
TMPFILES

  # Create the runtime directory now
  mkdir -p /var/run/pgbouncer
  chown postgres:postgres /var/run/pgbouncer

  # Create systemd service override to run as postgres user
  mkdir -p /etc/systemd/system/pgbouncer.service.d
  cat > /etc/systemd/system/pgbouncer.service.d/override.conf <<'OVERRIDE'
[Service]
User=postgres
Group=postgres
OVERRIDE

  # Reload systemd
  systemctl daemon-reload

  # Enable and start PgBouncer
  systemctl enable pgbouncer

  # Restart to apply configuration changes (especially listen_addr)
  systemctl restart pgbouncer

  # Wait for PgBouncer to be ready
  sleep 2

  if systemctl is-active --quiet pgbouncer; then
    log_success "PgBouncer started successfully on port 6432"
  else
    log_error "Failed to start PgBouncer"
    journalctl -u pgbouncer -n 50
    exit 1
  fi
}

# Create control database
create_control_database() {
  log_info "Creating control database for metadata..."

  sudo -u postgres psql <<SQLEOF
-- Create control database
CREATE DATABASE postgres_control;

-- Connect to control database
\c postgres_control;

-- ===================================================================
-- Enable core extensions
-- ===================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";       -- UUID generation
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements"; -- Query statistics

-- ===================================================================
-- Search, Text & Indexing extensions
-- ===================================================================
CREATE EXTENSION IF NOT EXISTS "pg_trgm";         -- Trigram indexes for ILIKE searches
CREATE EXTENSION IF NOT EXISTS "unaccent";        -- Remove accents (café → cafe)
CREATE EXTENSION IF NOT EXISTS "btree_gin";       -- Extra GIN index operator classes
CREATE EXTENSION IF NOT EXISTS "btree_gist";      -- Extra GiST index operator classes

-- ===================================================================
-- Types & Convenience extensions
-- ===================================================================
CREATE EXTENSION IF NOT EXISTS "citext";          -- Case-insensitive text type
CREATE EXTENSION IF NOT EXISTS "pgcrypto";        -- Cryptographic functions

-- ===================================================================
-- AI / Vector extensions
-- ===================================================================
CREATE EXTENSION IF NOT EXISTS "vector";          -- pgvector for embeddings/AI

-- ===================================================================
-- Chat & Messaging extensions
-- ===================================================================
CREATE EXTENSION IF NOT EXISTS "hstore";          -- Key-value pairs (message metadata)
CREATE EXTENSION IF NOT EXISTS "ltree";           -- Hierarchical data (chat threads)
CREATE EXTENSION IF NOT EXISTS "tablefunc";       -- Crosstab/pivot queries

-- ===================================================================
-- Geospatial extension
-- ===================================================================
CREATE EXTENSION IF NOT EXISTS "postgis";         -- Geographic objects support

-- ===================================================================
-- Databases table - stores metadata for all tenant databases
-- ===================================================================
CREATE TABLE databases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  database_name VARCHAR(255) UNIQUE NOT NULL,
  username VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  owner_email VARCHAR(255),
  friendly_name VARCHAR(255),
  max_connections INTEGER DEFAULT 20,
  status VARCHAR(50) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- ===================================================================
-- IP whitelist table - stores allowed IPs per database
-- ===================================================================
CREATE TABLE ip_whitelist (
  id SERIAL PRIMARY KEY,
  database_id UUID REFERENCES databases(id) ON DELETE CASCADE,
  ip_address VARCHAR(50) NOT NULL,
  description TEXT,
  added_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(database_id, ip_address)
);

-- ===================================================================
-- API keys table - stores API authentication keys
-- ===================================================================
CREATE TABLE api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key_hash VARCHAR(255) UNIQUE NOT NULL,
  name VARCHAR(255),
  permissions JSONB DEFAULT '{"databases": ["create", "read", "update", "delete"]}'::jsonb,
  created_at TIMESTAMP DEFAULT NOW(),
  expires_at TIMESTAMP,
  last_used_at TIMESTAMP
);

-- ===================================================================
-- Audit logs table - tracks all API operations
-- ===================================================================
CREATE TABLE audit_logs (
  id SERIAL PRIMARY KEY,
  api_key_id UUID REFERENCES api_keys(id),
  action VARCHAR(100) NOT NULL,
  resource_type VARCHAR(50),
  resource_id VARCHAR(255),
  ip_address VARCHAR(50),
  details JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- ===================================================================
-- Database statistics table - stores metrics
-- ===================================================================
CREATE TABLE database_stats (
  id SERIAL PRIMARY KEY,
  database_id UUID REFERENCES databases(id) ON DELETE CASCADE,
  size_bytes BIGINT,
  active_connections INTEGER,
  total_queries BIGINT,
  recorded_at TIMESTAMP DEFAULT NOW()
);

-- ===================================================================
-- Shadow databases table - stores shadow database information
-- Used for Prisma migrations, testing, and development
-- ===================================================================
CREATE TABLE shadow_databases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_database_id UUID REFERENCES databases(id) ON DELETE CASCADE,
  shadow_database_name VARCHAR(255) UNIQUE NOT NULL,
  shadow_username VARCHAR(255) UNIQUE NOT NULL,
  shadow_password_hash VARCHAR(255) NOT NULL,
  status VARCHAR(50) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT NOW(),
  synced_at TIMESTAMP,
  last_sync_status VARCHAR(50)
);

-- ===================================================================
-- Indexes for performance
-- ===================================================================
CREATE INDEX idx_databases_status ON databases(status);
CREATE INDEX idx_databases_created_at ON databases(created_at);
CREATE INDEX idx_databases_email ON databases(owner_email);
CREATE INDEX idx_ip_whitelist_db ON ip_whitelist(database_id);
CREATE INDEX idx_shadow_databases_parent ON shadow_databases(parent_database_id);
CREATE INDEX idx_shadow_databases_status ON shadow_databases(status);
CREATE INDEX idx_ip_whitelist_ip ON ip_whitelist(ip_address);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at);
CREATE INDEX idx_audit_logs_api_key ON audit_logs(api_key_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_database_stats_db ON database_stats(database_id);
CREATE INDEX idx_database_stats_recorded ON database_stats(recorded_at);

-- ===================================================================
-- Create API user for the NestJS application
-- ===================================================================
CREATE USER api_user WITH PASSWORD '$POSTGRES_ADMIN_PASSWORD';

-- Grant privileges on control database
GRANT CONNECT ON DATABASE postgres_control TO api_user;
GRANT ALL PRIVILEGES ON DATABASE postgres_control TO api_user;
GRANT ALL ON ALL TABLES IN SCHEMA public TO api_user;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO api_user;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO api_user;

-- Allow api_user to create databases and roles
ALTER USER api_user CREATEDB CREATEROLE;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO api_user;

-- ===================================================================
-- Create helpful views
-- ===================================================================

-- View: Active databases with stats
CREATE VIEW v_active_databases AS
SELECT
  d.id,
  d.database_name,
  d.friendly_name,
  d.owner_email,
  d.max_connections,
  d.status,
  d.created_at,
  COUNT(DISTINCT iw.id) as whitelisted_ips,
  pg_database_size(d.database_name) as size_bytes
FROM databases d
LEFT JOIN ip_whitelist iw ON d.id = iw.database_id
WHERE d.status = 'active'
GROUP BY d.id, d.database_name, d.friendly_name, d.owner_email,
         d.max_connections, d.status, d.created_at;

-- View: Audit summary
CREATE VIEW v_audit_summary AS
SELECT
  DATE(created_at) as date,
  action,
  COUNT(*) as count
FROM audit_logs
GROUP BY DATE(created_at), action
ORDER BY date DESC, count DESC;

GRANT SELECT ON v_active_databases TO api_user;
GRANT SELECT ON v_audit_summary TO api_user;

-- ===================================================================
-- Create utility functions
-- ===================================================================

-- Function: Get database size in human-readable format
CREATE OR REPLACE FUNCTION get_database_size_pretty(db_name TEXT)
RETURNS TEXT AS \$\$
BEGIN
  RETURN pg_size_pretty(pg_database_size(db_name));
END;
\$\$ LANGUAGE plpgsql;

-- Function: Clean old audit logs (keep 90 days)
CREATE OR REPLACE FUNCTION cleanup_old_audit_logs()
RETURNS INTEGER AS \$\$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM audit_logs
  WHERE created_at < NOW() - INTERVAL '90 days';
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
\$\$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_database_size_pretty(TEXT) TO api_user;
GRANT EXECUTE ON FUNCTION cleanup_old_audit_logs() TO api_user;

SQLEOF

  if [[ $? -eq 0 ]]; then
    log_success "Control database created successfully"
  else
    log_error "Failed to create control database"
    exit 1
  fi
}

# Setup SSL certificate auto-renewal
setup_ssl_renewal() {
  log_info "Setting up SSL certificate auto-renewal..."

  mkdir -p /etc/letsencrypt/renewal-hooks/post

  cat > /etc/letsencrypt/renewal-hooks/post/postgresql-reload.sh <<'RENEWAL_SCRIPT'
#!/bin/bash
# PostgreSQL SSL Certificate Renewal Hook
# This script runs after certbot renews the SSL certificate

# Find the actual domain directory (exclude README file)
DOMAIN=$(ls -d /etc/letsencrypt/live/*/ 2>/dev/null | head -n 1 | xargs basename)
SSL_DIR="/etc/postgresql/16/main/ssl"

# Copy renewed certificates
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem $SSL_DIR/server.crt
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem $SSL_DIR/server.key

# Set proper ownership and permissions
chown postgres:postgres $SSL_DIR/server.crt
chown postgres:postgres $SSL_DIR/server.key
chmod 600 $SSL_DIR/server.key
chmod 644 $SSL_DIR/server.crt

# Reload PostgreSQL to use new certificates
systemctl reload postgresql

echo "PostgreSQL SSL certificates renewed and reloaded at $(date)"
RENEWAL_SCRIPT

  chmod +x /etc/letsencrypt/renewal-hooks/post/postgresql-reload.sh

  # Test certbot renewal (dry-run)
  log_info "Testing certificate renewal process..."
  certbot renew --dry-run

  log_success "SSL auto-renewal configured"
}

# Create management scripts
create_management_scripts() {
  log_info "Creating management scripts..."

  # Script 1: Quick status check
  cat > /usr/local/bin/pg-status <<'STATUS_SCRIPT'
#!/bin/bash
echo "=== PostgreSQL Status ==="
systemctl status postgresql --no-pager -l
echo ""
echo "=== PgBouncer Status ==="
systemctl status pgbouncer --no-pager -l
echo ""
echo "=== PgBouncer Pools ==="
psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c "SHOW POOLS;" 2>/dev/null || echo "PgBouncer not accessible"
echo ""
echo "=== Active Connections ==="
sudo -u postgres psql -c "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;"
echo ""
echo "=== Database Sizes ==="
sudo -u postgres psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database WHERE datistemplate = false ORDER BY pg_database_size(datname) DESC;"
STATUS_SCRIPT
  chmod +x /usr/local/bin/pg-status

  # Script 4: PgBouncer status
  cat > /usr/local/bin/pg-bouncer-status <<'PGBOUNCER_STATUS_SCRIPT'
#!/bin/bash
echo "=== PgBouncer Service Status ==="
systemctl status pgbouncer --no-pager
echo ""
echo "=== PgBouncer Connection Pools ==="
psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c "SHOW POOLS;"
echo ""
echo "=== PgBouncer Statistics ==="
psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c "SHOW STATS;"
echo ""
echo "=== PgBouncer Databases ==="
psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c "SHOW DATABASES;"
PGBOUNCER_STATUS_SCRIPT
  chmod +x /usr/local/bin/pg-bouncer-status

  # Script 5: PgBouncer reload
  cat > /usr/local/bin/pg-bouncer-reload <<'PGBOUNCER_RELOAD_SCRIPT'
#!/bin/bash
echo "Reloading PgBouncer configuration..."
psql -h 127.0.0.1 -p 6432 -U postgres pgbouncer -c "RELOAD;"
echo "PgBouncer configuration reloaded"
PGBOUNCER_RELOAD_SCRIPT
  chmod +x /usr/local/bin/pg-bouncer-reload

  # Script 2: Backup control database
  cat > /usr/local/bin/pg-backup-control <<'BACKUP_SCRIPT'
#!/bin/bash
BACKUP_DIR="/var/backups/postgresql"
mkdir -p $BACKUP_DIR
BACKUP_FILE="$BACKUP_DIR/postgres_control_$(date +%Y%m%d_%H%M%S).sql.gz"
sudo -u postgres pg_dump postgres_control | gzip > $BACKUP_FILE
echo "Backup created: $BACKUP_FILE"
# Keep only last 7 days of backups
find $BACKUP_DIR -name "postgres_control_*.sql.gz" -mtime +7 -delete
BACKUP_SCRIPT
  chmod +x /usr/local/bin/pg-backup-control

  # Script 3: View active databases
  cat > /usr/local/bin/pg-list-databases <<'LIST_SCRIPT'
#!/bin/bash
sudo -u postgres psql -d postgres_control -c "SELECT * FROM v_active_databases ORDER BY created_at DESC;"
LIST_SCRIPT
  chmod +x /usr/local/bin/pg-list-databases

  log_success "Management scripts created"
}

# Setup daily backup cron
setup_backup_cron() {
  log_info "Setting up daily backup cron job..."

  # Create cron job for daily backup at 2 AM
  (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/pg-backup-control >> /var/log/postgresql-backup.log 2>&1") | crontab -

  log_success "Daily backup cron job configured"
}

# Get server IP
get_server_info() {
  SERVER_IP=$(hostname -I | awk '{print $1}')
  SERVER_HOSTNAME=$(hostname)
}

# Print final summary
print_summary() {
  get_server_info

  cat <<SUMMARY

${GREEN}╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║         PostgreSQL 16 Installation Complete!                  ║
║              DNS Challenge Edition                            ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝${NC}

${CYAN}═══════════════════════════════════════════════════════════════${NC}
${CYAN}Server Information${NC}
${CYAN}═══════════════════════════════════════════════════════════════${NC}

  Server IP:        ${SERVER_IP}
  Hostname:         ${SERVER_HOSTNAME}
  Domain:           ${DOMAIN}
  PostgreSQL Port:  5432 (Direct connection)
  PgBouncer Port:   6432 (Connection pooling - RECOMMENDED)
  PgBouncer Mode:   SESSION (Prisma/ORM compatible - prevents P1017 errors)
  SSL:              Enabled (Let's Encrypt via DNS Challenge)
  SSL Method:       $([ "$SSL_METHOD" == "1" ] && echo "Cloudflare DNS API (Automatic renewal)" || echo "Manual DNS (Manual renewal required)")

${CYAN}═══════════════════════════════════════════════════════════════${NC}
${CYAN}Database Credentials${NC}
${CYAN}═══════════════════════════════════════════════════════════════${NC}

  ${YELLOW}Superuser:${NC}
    Username:       postgres
    Password:       ${POSTGRES_ADMIN_PASSWORD}

  ${YELLOW}API User:${NC}
    Username:       api_user
    Password:       ${POSTGRES_ADMIN_PASSWORD}
    Database:       postgres_control

${CYAN}═══════════════════════════════════════════════════════════════${NC}
${CYAN}Connection Strings${NC}
${CYAN}═══════════════════════════════════════════════════════════════${NC}

  ${YELLOW}Via PgBouncer (RECOMMENDED for apps):${NC}
  postgresql://api_user:${POSTGRES_ADMIN_PASSWORD}@${DOMAIN}:6432/postgres_control?sslmode=require

  ${YELLOW}Direct PostgreSQL (for admin/migrations):${NC}
  postgresql://api_user:${POSTGRES_ADMIN_PASSWORD}@${DOMAIN}:5432/postgres_control?sslmode=require

  ${YELLOW}Using IP address:${NC}
  postgresql://api_user:${POSTGRES_ADMIN_PASSWORD}@${SERVER_IP}:6432/postgres_control?sslmode=require

  ${YELLOW}For local testing:${NC}
  postgresql://api_user:${POSTGRES_ADMIN_PASSWORD}@localhost:6432/postgres_control

${CYAN}═══════════════════════════════════════════════════════════════${NC}
${CYAN}SSL Certificate${NC}
${CYAN}═══════════════════════════════════════════════════════════════${NC}

  Certificate:      /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
  Private Key:      /etc/letsencrypt/live/${DOMAIN}/privkey.pem
  Auto-renewal:     Enabled (certbot timer)
  Renewal Hook:     /etc/letsencrypt/renewal-hooks/post/postgresql-reload.sh

SUMMARY

  if [[ "$SSL_METHOD" == "1" ]]; then
    cat <<CLOUDFLARE_INFO
  ${YELLOW}Cloudflare API Token:${NC}
    Stored in:      /root/.secrets/cloudflare.ini
    Auto-renewal:   Fully automated via DNS API

CLOUDFLARE_INFO
  else
    cat <<MANUAL_INFO
  ${RED}⚠ IMPORTANT - Manual DNS Renewal${NC}
  Since you used manual DNS challenge, you'll need to manually renew
  the certificate every 60-90 days by running:
    certbot renew
  And adding the DNS TXT record when prompted.

  ${YELLOW}Or switch to Cloudflare API for automatic renewal:${NC}
    1. Get Cloudflare API token
    2. Create /root/.secrets/cloudflare.ini with token
    3. Update certbot renewal config to use dns-cloudflare

MANUAL_INFO
  fi

  cat <<SUMMARY2
${CYAN}═══════════════════════════════════════════════════════════════${NC}
${CYAN}Configuration Files${NC}
${CYAN}═══════════════════════════════════════════════════════════════${NC}

  postgresql.conf:  /etc/postgresql/16/main/postgresql.conf
  pg_hba.conf:      /etc/postgresql/16/main/pg_hba.conf
  SSL Cert:         /etc/postgresql/16/main/ssl/server.crt
  SSL Key:          /etc/postgresql/16/main/ssl/server.key
  Logs:             /var/log/postgresql/postgresql-16-main.log

${CYAN}═══════════════════════════════════════════════════════════════${NC}
${CYAN}Management Commands${NC}
${CYAN}═══════════════════════════════════════════════════════════════${NC}

  ${YELLOW}Status & Monitoring:${NC}
    pg-status                    - Quick status overview
    pg-list-databases            - List all tenant databases
    systemctl status postgresql  - Service status

  ${YELLOW}Logs:${NC}
    tail -f /var/log/postgresql/postgresql-16-main.log
    journalctl -u postgresql -f

  ${YELLOW}Database Access:${NC}
    sudo -u postgres psql                    - Connect as superuser
    sudo -u postgres psql -d postgres_control  - Control database

  ${YELLOW}Backup & Restore:${NC}
    pg-backup-control            - Backup control database
    /var/backups/postgresql/     - Backup location

  ${YELLOW}Service Management:${NC}
    systemctl restart postgresql  - Restart service
    systemctl reload postgresql   - Reload config
    systemctl stop postgresql     - Stop service
    systemctl start postgresql    - Start service

${CYAN}═══════════════════════════════════════════════════════════════${NC}
${CYAN}Security Notes${NC}
${CYAN}═══════════════════════════════════════════════════════════════${NC}

  ${GREEN}✓${NC} Compatible with Nginx Proxy Manager (no port 80 conflict)
  ${GREEN}✓${NC} PostgreSQL only accepts SSL connections
  ${GREEN}✓${NC} Strong password authentication (scram-sha-256)
  ${GREEN}✓${NC} SSL certificate auto-renews (DNS challenge)
  ${GREEN}✓${NC} Daily backups configured (2 AM)

  ${RED}⚠${NC}  Save the credentials securely
  ${RED}⚠${NC}  Firewall: Ensure port 5432 is accessible from your API server
  ${RED}⚠${NC}  Monitor /var/log/postgresql/ regularly

${CYAN}═══════════════════════════════════════════════════════════════${NC}
${CYAN}Nginx Proxy Manager Integration${NC}
${CYAN}═══════════════════════════════════════════════════════════════${NC}

  ${YELLOW}PostgreSQL does NOT need reverse proxy${NC}
  PostgreSQL uses port 5432 (direct connection), not HTTP/HTTPS.

  ${YELLOW}If using NPM for API server:${NC}
  1. Deploy your Express API on this server (port 3000)
  2. In NPM, create a new Proxy Host:
     - Domain:       api.yourdomain.com
     - Forward to:   localhost:3000
     - SSL:          Request new SSL (or use existing)
     - Websockets:   Off
  3. API connects to PostgreSQL via: localhost:5432

${CYAN}═══════════════════════════════════════════════════════════════${NC}
${CYAN}Next Steps${NC}
${CYAN}═══════════════════════════════════════════════════════════════${NC}

  1. ${YELLOW}Test Connection:${NC}
     psql "postgresql://api_user:${POSTGRES_ADMIN_PASSWORD}@${DOMAIN}:5432/postgres_control?sslmode=require"

  2. ${YELLOW}Verify SSL:${NC}
     openssl s_client -connect ${DOMAIN}:5432 -starttls postgres

  3. ${YELLOW}Set up your Express API:${NC}
     - Use the connection string above in your .env file
     - Deploy the API (same server or remote)
     - Configure NPM if proxying the API

  4. ${YELLOW}Test from API server:${NC}
     node -e "const {Pool}=require('pg');const p=new Pool({connectionString:'postgresql://api_user:${POSTGRES_ADMIN_PASSWORD}@${DOMAIN}:5432/postgres_control?sslmode=require'});p.query('SELECT NOW()').then(r=>console.log(r.rows[0])).catch(console.error).finally(()=>p.end())"

  5. ${YELLOW}Monitor:${NC}
     Run 'pg-status' to check system health

${CYAN}═══════════════════════════════════════════════════════════════${NC}
${CYAN}Important Files to Save${NC}
${CYAN}═══════════════════════════════════════════════════════════════${NC}

  Save this output to: installation_details.txt

  ${YELLOW}Command to save:${NC}
  cat > ~/postgresql_installation_\$(date +%Y%m%d).txt <<'EOF'
  Domain: ${DOMAIN}
  Server IP: ${SERVER_IP}
  Admin Password: ${POSTGRES_ADMIN_PASSWORD}
  Connection: postgresql://api_user:${POSTGRES_ADMIN_PASSWORD}@${DOMAIN}:5432/postgres_control?sslmode=require
  SSL Method: $([ "$SSL_METHOD" == "1" ] && echo "Cloudflare DNS API" || echo "Manual DNS")
  EOF

${GREEN}╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║              Installation completed successfully!              ║
║                                                                ║
║    Your PostgreSQL SaaS platform is ready for production!     ║
║         Works seamlessly with Nginx Proxy Manager!            ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝${NC}

SUMMARY2
}

# Main installation function
main() {
  show_banner
  ensure_root
  get_configuration

  log_info "Starting installation..."
  echo ""

  update_system
  install_postgresql
  install_dependencies
  obtain_ssl_certificate
  configure_postgresql_ssl
  configure_postgresql
  start_postgresql
  set_postgres_password
  configure_pgbouncer
  create_control_database
  setup_pgbouncer_auth
  start_pgbouncer
  setup_ssl_renewal
  create_management_scripts
  setup_backup_cron

  echo ""
  log_success "All installation steps completed!"
  echo ""

  print_summary
}

# Run main function
main "$@"
