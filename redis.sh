#!/usr/bin/env bash

# ===================================
# Redis Installation Script for Multi-Site AI Cache
# Optimized for AI workloads with multi-site support
# Tested on Ubuntu 20.04/22.04/24.04
# ===================================

# Ensure the script is run as root or with sudo
if [ "$(id -u)" != "0" ]; then
    echo "Please run this script as root (sudo)."
    exit 1
fi

# Get Redis password
read -sp "Enter the desired Redis password (strong password recommended): " REDIS_PASS
echo

if [ -z "$REDIS_PASS" ]; then
    echo "ERROR: Password cannot be empty"
    exit 1
fi

# Get server memory for automatic RAM allocation
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
# Use 40% of server memory for Redis, min 512MB, max 4GB
REDIS_MEMORY=$((TOTAL_MEM_MB * 40 / 100))
if [ $REDIS_MEMORY -lt 512 ]; then
    REDIS_MEMORY=512
elif [ $REDIS_MEMORY -gt 4096 ]; then
    REDIS_MEMORY=4096
fi

echo "====================================="
echo "Redis Installation & Configuration"
echo "====================================="
echo "Total system memory: ${TOTAL_MEM_MB}MB"
echo "Allocating ${REDIS_MEMORY}MB for Redis"
echo "====================================="

# 1. Stop and purge any existing Redis installation
echo "Removing previous Redis installation (if any)..."
systemctl stop redis-server 2>/dev/null || true
apt purge redis-server redis-tools -y 2>/dev/null || true
apt autoremove -y

# 2. Install Redis
echo "Installing Redis..."
apt update
apt install redis-server -y

# Check if it starts with default config
systemctl start redis-server
sleep 2

if ! systemctl is-active --quiet redis-server; then
    echo "ERROR: Redis failed to start with default configuration."
    echo "Check 'systemctl status redis-server' and 'journalctl -xeu redis-server.service' for details."
    exit 1
fi

echo "Redis started successfully with default configuration."

# 3. Configure Redis for multi-site AI caching workload
REDIS_CONF="/etc/redis/redis.conf"

echo "Configuring Redis for multi-site AI caching workload..."

# Backup the original configuration
BACKUP_FILE="${REDIS_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
cp $REDIS_CONF $BACKUP_FILE
echo "Config backed up to: $BACKUP_FILE"

# Stop Redis before modifying config
systemctl stop redis-server

# Create optimized configuration file
cat > $REDIS_CONF << EOF
# Redis Configuration for Multi-Site AI Cache
# Generated on $(date)
# Original backup: $BACKUP_FILE

# ===================================
# NETWORK
# ===================================
bind 0.0.0.0
protected-mode yes
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300

# ===================================
# GENERAL
# ===================================
daemonize no
supervised systemd
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16

# ===================================
# SECURITY
# ===================================
requirepass ${REDIS_PASS}

# Disable dangerous commands
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command DEBUG ""

# ===================================
# MEMORY MANAGEMENT
# ===================================
maxmemory ${REDIS_MEMORY}mb
maxmemory-policy allkeys-lru
maxmemory-samples 10

# ===================================
# LAZY FREEING (AI Cache Optimization)
# ===================================
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes

# ===================================
# APPEND ONLY MODE (AOF)
# ===================================
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite yes
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes

# ===================================
# SNAPSHOTTING (RDB)
# ===================================
save 900 1
save 300 100
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis

# ===================================
# REPLICATION
# ===================================
# replica-serve-stale-data yes
# replica-read-only yes

# ===================================
# PERFORMANCE
# ===================================
activerehashing yes
hz 10

# Client output buffer limits
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60

# Max clients
maxclients 10000

# ===================================
# SLOW LOG
# ===================================
slowlog-log-slower-than 10000
slowlog-max-len 128

# ===================================
# LATENCY MONITOR
# ===================================
latency-monitor-threshold 100

# ===================================
# EVENT NOTIFICATION
# ===================================
notify-keyspace-events ""

# ===================================
# ADVANCED CONFIG
# ===================================
hash-max-listpack-entries 512
hash-max-listpack-value 64
list-max-listpack-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-listpack-entries 128
zset-max-listpack-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
EOF

# Set correct permissions
chown redis:redis $REDIS_CONF
chmod 640 $REDIS_CONF

# 4. Start Redis with new configuration
echo "Starting Redis with new configuration..."
systemctl start redis-server

# Wait for Redis to fully start (give it time to initialize)
echo "Waiting for Redis to start..."
for i in {1..10}; do
    sleep 1
    if systemctl is-active --quiet redis-server; then
        echo "Redis is active (attempt $i)"
        sleep 1  # Extra second to ensure it's fully ready
        break
    fi
    echo "Waiting... ($i/10)"
done

# 5. Verify Redis started successfully
if systemctl is-active --quiet redis-server; then
    # Get server's IP address for connection string
    SERVER_IP=$(hostname -I | awk '{print $1}')

    echo ""
    echo "=========================================================="
    echo "✅ Redis installation and configuration completed successfully!"
    echo "=========================================================="
    echo ""
    echo "📊 Redis Configuration Summary:"
    echo "• Memory allocated: ${REDIS_MEMORY}MB"
    echo "• Eviction policy: allkeys-lru (removes least recently used keys)"
    echo "• Persistence: Hybrid (RDB + AOF for durability)"
    echo "• Network: 0.0.0.0:6379 (accessible from all interfaces)"
    echo "• Security: Password authentication ENABLED"
    echo "• Databases: 16 (DB 0-15 for multi-site isolation)"
    echo "• Max connections: 10,000"
    echo ""
    echo "🔗 Redis Connection Information:"
    echo "• Host: ${SERVER_IP}"
    echo "• Port: 6379"
    echo "• Password: ${REDIS_PASS}"
    echo ""
    echo "🔐 For your applications, use this connection URL:"
    echo "REDIS_URL=redis://:${REDIS_PASS}@${SERVER_IP}:6379"
    echo ""
    echo "🏗️ MULTI-SITE ARCHITECTURE (Single Redis URL for All Sites):"
    echo "• Same connection URL for all sites"
    echo "• Use key prefixes to isolate sites: site:{site_id}:{type}:{key}"
    echo "• Examples:"
    echo "  - Site A products: site:store_a:products:123"
    echo "  - Site B AI cache: site:store_b:ai:embeddings:doc_456"
    echo "  - Site C sessions: site:store_c:session:user_789"
    echo ""
    echo "🤖 AI CACHE FEATURES ENABLED:"
    echo "• Large payload support (up to 512MB per key)"
    echo "• Lazy-free eviction (non-blocking cache invalidation)"
    echo "• Hybrid persistence (RDB + AOF for durability)"
    echo "• Slow query logging (>10ms tracked)"
    echo "• 10,000 max concurrent connections"
    echo ""
    echo "💡 OPTIONAL: For vector search, install Redis Stack:"
    echo "   docker run -d -p 6380:6379 redis/redis-stack-server:latest"
    echo "   (Use port 6380 to avoid conflict with this Redis)"
    echo ""
    echo "📝 RECOMMENDED TTL STRATEGIES:"
    echo "• Embeddings cache: 600s (10 min) - For temporary computations"
    echo "• LLM completions: 120-3600s - Volatile to stable queries"
    echo "• Chat sessions: No TTL or manual cleanup"
    echo "• Product cache: 3600s (1 hour) - Standard e-commerce"
    echo ""
    echo "⚠️ IMPORTANT SECURITY NOTES:"
    echo "1. Redis is accessible from ALL networks (0.0.0.0:6379)"
    echo "2. Protected mode: ENABLED (password required for all connections)"
    echo "3. HIGHLY RECOMMENDED: Set up firewall rules to restrict access"
    echo "4. Original config backed up at ${BACKUP_FILE}"
    echo ""
    echo "🔒 CRITICAL: Configure firewall NOW:"
    echo "  sudo ufw allow from YOUR_APP_SERVER_IP to any port 6379"
    echo "  sudo ufw deny 6379  # Block all other IPs"
    echo "  sudo ufw enable"
    echo ""
    echo "✅ Test your Redis connection:"
    echo "  redis-cli -h ${SERVER_IP} -p 6379 -a ${REDIS_PASS} ping"
    echo "  Expected response: PONG"
    echo ""
    echo "=========================================================="

    # Enable auto-start on boot
    systemctl enable redis-server >/dev/null 2>&1

else
    echo "❌ Redis failed to start after configuration changes."
    echo ""
    echo "Restoring backup configuration..."
    cp $BACKUP_FILE $REDIS_CONF
    systemctl start redis-server
    echo "Reverted to backup: $BACKUP_FILE"
    echo ""
    echo "Check these logs for details:"
    echo "  sudo journalctl -xeu redis-server.service --no-pager | tail -50"
    echo "  sudo tail -50 /var/log/redis/redis-server.log"
    echo ""
    echo "Test config syntax:"
    echo "  redis-server /etc/redis/redis.conf --test-memory 1"
    echo ""
    exit 1
fi

# 6. Create an enhanced monitor script for Redis with multi-site stats
MONITOR_SCRIPT="/usr/local/bin/redis-monitor.sh"
cat > $MONITOR_SCRIPT << 'MONITOR_EOF'
#!/bin/bash
# Enhanced Redis monitoring script for AI cache + multi-site

REDIS_PASS='REDIS_PASSWORD_PLACEHOLDER'

echo "========================================"
echo "Redis Multi-Site AI Cache Monitor"
echo "========================================"
echo ""

echo "📊 Memory Usage:"
redis-cli -a $REDIS_PASS info memory 2>/dev/null | grep -E 'used_memory_human|used_memory_peak_human|maxmemory_human|mem_fragmentation_ratio' | sed 's/^/  /'

echo ""
echo "👥 Connections:"
redis-cli -a $REDIS_PASS info clients 2>/dev/null | grep -E 'connected_clients|blocked_clients|maxclients' | sed 's/^/  /'

echo ""
echo "🔑 Keys per Database:"
for db in {0..15}; do
  count=$(redis-cli -a $REDIS_PASS -n $db DBSIZE 2>/dev/null)
  if [ "$count" != "0" ] && [ -n "$count" ]; then
    echo "  DB $db: $count keys"
  fi
done

echo ""
echo "🐌 Slow Queries (last 5):"
redis-cli -a $REDIS_PASS SLOWLOG GET 5 2>/dev/null | grep -E 'duration|cmd' | head -10 | sed 's/^/  /'

echo ""
echo "⚡ Stats:"
redis-cli -a $REDIS_PASS info stats 2>/dev/null | grep -E 'total_commands_processed|instantaneous_ops_per_sec|keyspace_hits|keyspace_misses|evicted_keys' | sed 's/^/  /'

echo ""
echo "🎯 Cache Hit Rate:"
redis-cli -a $REDIS_PASS info stats 2>/dev/null | awk -F: '/keyspace_hits/{hits=$2} /keyspace_misses/{misses=$2} END{if(hits+misses>0) printf "  %.2f%% (Hits: %d, Misses: %d)\n", (hits/(hits+misses))*100, hits, misses}'

echo "========================================"
MONITOR_EOF

# Replace placeholder with actual password
sed -i "s/REDIS_PASSWORD_PLACEHOLDER/${REDIS_PASS}/" $MONITOR_SCRIPT
chmod +x $MONITOR_SCRIPT

echo ""
echo "✅ Enhanced monitoring script created: $MONITOR_SCRIPT"
echo "   Run it anytime with: sudo $MONITOR_SCRIPT"
echo ""
