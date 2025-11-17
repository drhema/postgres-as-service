#!/usr/bin/env bash

# ===================================
# Enhanced Redis Installation Script for Phoenix Ecommerce App
# Optimized for caching workloads with security and performance settings
# ===================================

# Ensure the script is run as root or with sudo
if [ "$(id -u)" != "0" ]; then
    echo "Please run this script as root (sudo)."
    exit 1
fi

# Get Redis password
read -sp "Enter the desired Redis password (strong password recommended): " REDIS_PASS
echo

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
systemctl stop redis-server || true
apt purge redis-server redis-tools -y
apt autoremove -y

# 2. Install Redis
echo "Installing Redis..."
apt update
apt install redis-server -y

# Check if it starts with default config
systemctl restart redis-server
if ! systemctl is-active --quiet redis-server; then
    echo "ERROR: Redis failed to start with default configuration."
    echo "Check 'systemctl status redis-server' and 'journalctl -xeu redis-server.service' for details."
    exit 1
fi

echo "Redis started successfully with default configuration."

# 3. Configure Redis for ecommerce caching workload
REDIS_CONF="/etc/redis/redis.conf"

echo "Configuring Redis for ecommerce caching workload..."

# Backup the original configuration
cp $REDIS_CONF ${REDIS_CONF}.backup

# --- SECURITY SETTINGS ---
echo "Configuring security settings..."

# Set password
sed -i 's/^# requirepass .*/requirepass '"$REDIS_PASS"'/' $REDIS_CONF
grep -q "^requirepass" $REDIS_CONF || echo "requirepass $REDIS_PASS" >> $REDIS_CONF

# Network settings - Bind to all interfaces for multi-site access
sed -i 's/^bind .*/bind 0.0.0.0/' $REDIS_CONF
sed -i 's/^protected-mode .*/protected-mode yes/' $REDIS_CONF

# --- MEMORY MANAGEMENT ---
echo "Configuring memory management..."

# Add memory limit and policy
echo "# Memory management settings - optimized for cache workload" >> $REDIS_CONF
echo "maxmemory ${REDIS_MEMORY}mb" >> $REDIS_CONF
echo "maxmemory-policy allkeys-lru" >> $REDIS_CONF
echo "" >> $REDIS_CONF

# --- PERSISTENCE SETTINGS ---
echo "Optimizing persistence settings for caching..."

# Adjust persistence for better cache performance
# Comment out all existing save directives
sed -i 's/^save /# save /' $REDIS_CONF

# Add our optimized persistence settings
echo "# Cache-optimized persistence (less frequent saves)" >> $REDIS_CONF
echo "save 900 1" >> $REDIS_CONF      # Save if at least 1 key changed in 15 minutes
echo "save 300 100" >> $REDIS_CONF    # Save if at least 100 keys changed in 5 minutes
echo "" >> $REDIS_CONF

# --- PERFORMANCE TUNING ---
echo "Applying performance optimizations..."

# Performance settings
echo "# Performance optimizations for AI/ML and ecommerce caching" >> $REDIS_CONF
echo "tcp-keepalive 300" >> $REDIS_CONF          # Keep connections alive
echo "timeout 0" >> $REDIS_CONF                  # Don't timeout clients
echo "databases 16" >> $REDIS_CONF               # 16 DBs for multi-site isolation (DB 0-15)
echo "loglevel notice" >> $REDIS_CONF            # Reduced logging for performance

# Vector search optimization (Redis Stack/Search)
echo "# Vector search workers for parallel query processing" >> $REDIS_CONF
echo "# Note: Only applies if using RediSearch/Redis Stack" >> $REDIS_CONF
echo "search-workers 6" >> $REDIS_CONF           # 6 concurrent search threads for AI workloads

echo "# Disable expensive commands in production" >> $REDIS_CONF
echo "rename-command FLUSHALL \"\"" >> $REDIS_CONF  # Disable dangerous commands
echo "rename-command FLUSHDB \"\"" >> $REDIS_CONF
echo "rename-command DEBUG \"\"" >> $REDIS_CONF
echo "" >> $REDIS_CONF

# --- LATENCY SETTINGS ---
echo "Optimizing for low latency..."
echo "# Latency optimizations" >> $REDIS_CONF
echo "no-appendfsync-on-rewrite yes" >> $REDIS_CONF  # Don't sync during rewrites
echo "activerehashing yes" >> $REDIS_CONF           # Enable rehashing for faster reads
echo "" >> $REDIS_CONF

# --- AI CACHE OPTIMIZATIONS ---
echo "Configuring AI cache optimizations..."
echo "# AI/ML Cache optimizations for large payloads and multi-site" >> $REDIS_CONF
echo "maxmemory-samples 10" >> $REDIS_CONF          # More accurate LRU
echo "lazyfree-lazy-eviction yes" >> $REDIS_CONF    # Non-blocking evictions
echo "lazyfree-lazy-expire yes" >> $REDIS_CONF
echo "lazyfree-lazy-server-del yes" >> $REDIS_CONF
echo "tcp-backlog 511" >> $REDIS_CONF               # Handle connection bursts
echo "maxclients 10000" >> $REDIS_CONF              # Support many sites/connections
echo "hz 10" >> $REDIS_CONF                         # Background task frequency
echo "slowlog-log-slower-than 10000" >> $REDIS_CONF # Log queries >10ms
echo "slowlog-max-len 128" >> $REDIS_CONF
echo "" >> $REDIS_CONF

# --- HYBRID PERSISTENCE FOR AI ---
echo "# Hybrid persistence: RDB for snapshots + AOF for durability" >> $REDIS_CONF
echo "appendonly yes" >> $REDIS_CONF
echo "appendfsync everysec" >> $REDIS_CONF
echo "auto-aof-rewrite-percentage 100" >> $REDIS_CONF
echo "auto-aof-rewrite-min-size 64mb" >> $REDIS_CONF
echo "" >> $REDIS_CONF

# --- TLS/SSL REMINDER ---
echo "# TLS/SSL is recommended for production but requires manual setup" >> $REDIS_CONF
echo "# See https://redis.io/topics/encryption" >> $REDIS_CONF
echo "" >> $REDIS_CONF

# --- CLIENT OUTPUT/INPUT BUFFER LIMITS ---
echo "# Client buffer limits to prevent slow clients from affecting server" >> $REDIS_CONF
echo "client-output-buffer-limit normal 0 0 0" >> $REDIS_CONF
echo "client-output-buffer-limit replica 256mb 64mb 60" >> $REDIS_CONF
echo "" >> $REDIS_CONF

# 4. Restart Redis to apply changes
systemctl restart redis-server

# 5. Check if Redis starts with the new configuration
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
    echo "• Eviction policy: allkeys-lru (removes least recently used keys when memory is full)"
    echo "• Persistence: Optimized for caching (less frequent saves)"
    echo "• Network: Listening on all interfaces (0.0.0.0:6379)"
    echo "• Security: Password authentication enabled"
    echo ""
    echo "🔗 Redis Connection Information:"
    echo "• Host: ${SERVER_IP}"
    echo "• Port: 6379"
    echo "• Redis CLI: redis-cli -h ${SERVER_IP} -p 6379 -a ${REDIS_PASS}"
    echo ""
    echo "🔐 For your Phoenix application, add this to your .env file:"
    echo "REDIS_URL=redis://:${REDIS_PASS}@${SERVER_IP}:6379"
    echo ""
    echo "🏗️ MULTI-SITE ARCHITECTURE (Single Redis URL for All Sites):"
    echo "• Same connection URL for all sites: REDIS_URL=redis://:${REDIS_PASS}@${SERVER_IP}:6379"
    echo "• Use key prefixes to isolate sites: site:{site_id}:{type}:{key}"
    echo "• Examples:"
    echo "  - Site A products: site:site_a:products:123"
    echo "  - Site B AI cache: site:site_b:ai:embeddings:doc_456"
    echo "  - Site C sessions: site:site_c:session:user_789"
    echo ""
    echo "🤖 AI CACHE FEATURES ENABLED:"
    echo "• Large payload support (up to 512MB per key)"
    echo "• Lazy-free eviction (non-blocking cache invalidation)"
    echo "• Hybrid persistence (RDB + AOF for durability)"
    echo "• Slow query logging (>10ms tracked)"
    echo "• 10,000 max concurrent connections"
    echo "• 6 search workers for vector/AI queries (if using Redis Stack)"
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
    echo "4. Original config backed up at ${REDIS_CONF}.backup"
    echo ""
    echo "🔒 CRITICAL: Configure firewall NOW:"
    echo "sudo ufw allow from YOUR_APP_SERVER_IP to any port 6379"
    echo "sudo ufw deny 6379  # Block all other IPs"
    echo "sudo ufw enable"
    echo ""
    echo "To test your Redis connection:"
    echo "redis-cli -h ${SERVER_IP} -p 6379 -a ${REDIS_PASS} ping"
    echo "Expected response: PONG"
    echo "=========================================================="
else
    echo "Redis failed to start after configuration changes."
    echo "Reverting to original configuration..."
    cp ${REDIS_CONF}.backup $REDIS_CONF
    systemctl restart redis-server
    
    echo "Check these logs for details:"
    echo "- systemctl status redis-server"
    echo "- journalctl -xeu redis-server.service"
    exit 1
fi

# 6. Create an enhanced monitor script for Redis with multi-site stats
MONITOR_SCRIPT="/usr/local/bin/redis-monitor.sh"
echo "#!/bin/bash" > $MONITOR_SCRIPT
echo "# Enhanced Redis monitoring script for AI cache + multi-site" >> $MONITOR_SCRIPT
echo "REDIS_PASS='${REDIS_PASS}'" >> $MONITOR_SCRIPT
echo "" >> $MONITOR_SCRIPT
echo "echo \"========================================\"" >> $MONITOR_SCRIPT
echo "echo \"Redis Multi-Site AI Cache Monitor\"" >> $MONITOR_SCRIPT
echo "echo \"========================================\"" >> $MONITOR_SCRIPT
echo "echo \"\"" >> $MONITOR_SCRIPT
echo "echo \"📊 Memory Usage:\"" >> $MONITOR_SCRIPT
echo "redis-cli -a \$REDIS_PASS info memory | grep -E '(used_memory_human|used_memory_peak_human|maxmemory_human|mem_fragmentation_ratio)'" >> $MONITOR_SCRIPT
echo "echo \"\"" >> $MONITOR_SCRIPT
echo "echo \"👥 Connections:\"" >> $MONITOR_SCRIPT
echo "redis-cli -a \$REDIS_PASS info clients | grep -E '(connected_clients|blocked_clients|maxclients)'" >> $MONITOR_SCRIPT
echo "echo \"\"" >> $MONITOR_SCRIPT
echo "echo \"🔑 Keys per Database:\"" >> $MONITOR_SCRIPT
echo "for db in {0..15}; do" >> $MONITOR_SCRIPT
echo "  count=\$(redis-cli -a \$REDIS_PASS -n \$db DBSIZE | awk '{print \$2}')" >> $MONITOR_SCRIPT
echo "  if [ \"\$count\" != \"0\" ]; then" >> $MONITOR_SCRIPT
echo "    echo \"  DB \$db: \$count keys\"" >> $MONITOR_SCRIPT
echo "  fi" >> $MONITOR_SCRIPT
echo "done" >> $MONITOR_SCRIPT
echo "echo \"\"" >> $MONITOR_SCRIPT
echo "echo \"🐌 Slow Queries (last 5):\"" >> $MONITOR_SCRIPT
echo "redis-cli -a \$REDIS_PASS SLOWLOG GET 5 | grep -E '(duration|cmd)' | head -10" >> $MONITOR_SCRIPT
echo "echo \"\"" >> $MONITOR_SCRIPT
echo "echo \"⚡ Stats:\"" >> $MONITOR_SCRIPT
echo "redis-cli -a \$REDIS_PASS info stats | grep -E '(total_commands_processed|instantaneous_ops_per_sec|keyspace_hits|keyspace_misses|evicted_keys)'" >> $MONITOR_SCRIPT
echo "echo \"\"" >> $MONITOR_SCRIPT
echo "echo \"🎯 Cache Hit Rate:\"" >> $MONITOR_SCRIPT
echo "redis-cli -a \$REDIS_PASS info stats | awk -F: '/keyspace_hits/{hits=\$2} /keyspace_misses/{misses=\$2} END{if(hits+misses>0) printf \"  %.2f%% (Hits: %d, Misses: %d)\\n\", (hits/(hits+misses))*100, hits, misses}'" >> $MONITOR_SCRIPT
echo "echo \"========================================\"" >> $MONITOR_SCRIPT
chmod +x $MONITOR_SCRIPT

echo "✅ Added enhanced Redis monitoring script: $MONITOR_SCRIPT"
echo "Run it anytime with: sudo $MONITOR_SCRIPT"