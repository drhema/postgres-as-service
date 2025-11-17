# Server & PostgreSQL Benchmarking Guide

Complete benchmarking suite for testing server and PostgreSQL performance to determine multi-tenant hosting capacity.

## Overview

This benchmark suite tests:

1. **Server Performance**
   - CPU (single and multi-core)
   - Memory (throughput and latency)
   - Disk I/O (sequential and random)
   - Network (throughput)
   - File system operations

2. **PostgreSQL Performance**
   - Connection overhead
   - Query performance (SELECT, INSERT, UPDATE)
   - Transaction throughput (TPS)
   - Complex queries and JOINs
   - Concurrent operations
   - Index performance

3. **Hosting Capacity Analysis**
   - Estimated database count
   - Concurrent connection capacity
   - Recommended workload types
   - Configuration recommendations

## Quick Start

### Option 1: Run Complete Benchmark Suite (Recommended)

```bash
# SSH into your server
ssh root@94.130.137.39

# Clone or download the repository
# (If you have the files already, skip to running)

# Run the comprehensive benchmark
sudo ./run-benchmarks.sh
```

This will:
- Test server performance
- Test PostgreSQL performance
- Generate a comprehensive report with recommendations
- Save all results to a timestamped directory

### Option 2: Run Individual Benchmarks

#### Server Benchmark Only

```bash
sudo ./benchmark-server.sh
```

Tests: CPU, Memory, Disk I/O, Network, File System

#### PostgreSQL Benchmark Only

```bash
./benchmark-postgres.sh [host] [port] [user]

# Examples:
./benchmark-postgres.sh localhost 5432 postgres
./benchmark-postgres.sh db.yourdomain.com 5432 postgres
```

Tests: Database operations, query performance, transactions

## Requirements

### System Requirements

- Ubuntu Server (18.04+, 20.04, 22.04, or 24.04)
- Root or sudo access
- At least 2GB free disk space for tests
- PostgreSQL installed and running

### Automatic Tool Installation

The benchmark scripts will automatically install required tools:
- `sysbench` - CPU and memory benchmarking
- `fio` - Advanced disk I/O testing
- `hdparm` - Disk performance testing
- `iperf3` - Network testing
- `bc` - Calculations

## Understanding the Results

### Server Performance Metrics

#### CPU Performance

```
Single-thread: 2500 events/sec
Multi-thread: 18000 events/sec
Scaling: 7.2x
```

**What this means:**
- **Single-thread**: Higher is better. Good: >2000, Fair: 1000-2000, Poor: <1000
- **Multi-thread**: Should scale with core count. Check scaling efficiency.
- **Scaling**: Ideal is close to number of cores. >0.7x per core is good.

**Impact on hosting:**
- High single-thread = Better for complex queries
- Good multi-core = Can handle many concurrent databases

#### Memory Performance

```
Throughput: 15000 MB/sec
Latency: 2.5s
```

**What this means:**
- **Throughput**: Higher is better. DDR4: 10000-20000 MB/s
- **Latency**: Lower is better

**Impact on hosting:**
- Fast memory = Better caching and query performance
- Large memory = More databases can fit in cache

#### Disk I/O Performance

```
Sequential read: 500 MB/s
Random read IOPS: 50000
Random write IOPS: 30000
```

**What this means:**
- **Sequential**: SSD: >400 MB/s, HDD: 80-160 MB/s
- **Random IOPS**: SSD: >10000, HDD: 80-160
- **NVMe SSD**: >100000 IOPS

**Impact on hosting:**
- High IOPS = Better for many small concurrent queries
- High throughput = Better for large data scans
- **Critical**: Use SSD or NVMe for production databases

### PostgreSQL Performance Metrics

#### Transaction Performance

```
TPS (Transactions Per Second): 850 TPS
Connection time: 0.05s per connection
```

**What this means:**
- **TPS**: Transactions processed per second
  - Excellent: >1000 TPS
  - Good: 500-1000 TPS
  - Fair: 200-500 TPS
  - Poor: <200 TPS

- **Connection time**: Time to establish connection
  - Good: <0.1s
  - Fair: 0.1-0.3s
  - Poor: >0.3s (consider connection pooling)

#### Query Performance

```
10,000 INSERTs: 2.5s (4000 rows/sec)
10,000 row scan: 0.15s
Indexed lookup: 0.003s
Complex JOIN: 0.8s
```

**What this means:**
- **INSERT rate**: How fast data can be added
- **Scan time**: Full table read performance
- **Indexed lookup**: Should be very fast (<0.01s)
- **JOINs**: Complex query performance

### Capacity Ratings

The benchmark provides an overall capacity rating:

#### EXCELLENT
- **Specs**: 8+ cores, 16GB+ RAM, NVMe/SSD
- **Capacity**: 50-100 databases
- **Connections**: 1000-2000 concurrent (with pooling)
- **Use case**: Production multi-tenant SaaS

#### GOOD
- **Specs**: 4+ cores, 8GB+ RAM, SSD
- **Capacity**: 20-50 databases
- **Connections**: 500-1000 concurrent (with pooling)
- **Use case**: Small to medium production workloads

#### FAIR
- **Specs**: 2+ cores, 4GB+ RAM, SSD
- **Capacity**: 10-20 databases
- **Connections**: 200-500 concurrent (with pooling)
- **Use case**: Development and testing

#### LIMITED
- **Specs**: <2 cores, <4GB RAM, or HDD
- **Capacity**: 5-10 databases
- **Connections**: 50-200 concurrent
- **Use case**: Development only

## Interpreting Your Results

### Example Benchmark Output

Let's say your server shows:

```
CPU: 4 cores, 2200 events/sec (single), 7500 events/sec (multi)
RAM: 8GB
Disk: SSD with 40000 random read IOPS
PostgreSQL TPS: 650
```

**Analysis:**

✓ **Good**:
- CPU single-thread performance is solid
- SSD with good IOPS
- Decent TPS for small workloads

⚠ **Watch out**:
- Only 4 cores - limits concurrent database count
- 8GB RAM - may need upgrade if databases grow
- TPS could be higher - check PostgreSQL config

**Recommendation**:
- Can host 20-30 small databases (<500MB each)
- Use PgBouncer for connection pooling
- Monitor memory usage closely
- Plan to upgrade to 8 cores / 16GB RAM as you grow

## Optimization Recommendations

### Based on Your Benchmark Results

#### If CPU is the Bottleneck
- Optimize complex queries
- Add database indexes
- Consider read replicas
- Upgrade to more cores

#### If Memory is the Bottleneck
- Increase PostgreSQL `shared_buffers`
- Add more RAM
- Optimize memory-intensive queries
- Reduce `work_mem` if too high

#### If Disk is the Bottleneck
- **Critical**: Upgrade HDD to SSD or NVMe
- Tune PostgreSQL I/O settings
- Add indexes to reduce disk scans
- Consider separate disk for WAL files

#### If Network is the Bottleneck
- Check for bandwidth limits
- Optimize data transfer sizes
- Use compression for large transfers
- Consider CDN for static assets

### PostgreSQL Configuration Tuning

Based on your server specs, adjust `/etc/postgresql/16/main/postgresql.conf`:

```ini
# For 8GB RAM server
shared_buffers = 2GB              # 25% of RAM
effective_cache_size = 6GB        # 75% of RAM
work_mem = 32MB                   # For sorting/hashing
maintenance_work_mem = 512MB      # For VACUUM, indexes
max_connections = 200             # Adjust based on needs

# For SSD
random_page_cost = 1.1            # Default 4.0 is for HDD
effective_io_concurrency = 200    # SSD can handle more

# For connection pooling
max_connections = 100             # Lower if using PgBouncer

# Logging for monitoring
log_min_duration_statement = 1000  # Log queries > 1s
log_connections = on
log_disconnections = on
```

**After changing config:**
```bash
sudo systemctl restart postgresql
```

### System Tuning

#### 1. Disable Swap for Database Performance

```bash
# Check current swappiness
cat /proc/sys/vm/swappiness

# Set to 10 (optimal for databases)
sudo sysctl vm.swappiness=10

# Make permanent
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
```

#### 2. Increase File Limits

```bash
# Edit limits
sudo nano /etc/security/limits.conf

# Add these lines:
postgres soft nofile 65536
postgres hard nofile 65536
```

#### 3. Optimize TCP Settings

```bash
# For high connection count
sudo sysctl -w net.core.somaxconn=1024
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=2048

# Make permanent
echo "net.core.somaxconn=1024" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog=2048" | sudo tee -a /etc/sysctl.conf
```

### Connection Pooling with PgBouncer

For hosting many applications, install PgBouncer:

```bash
# Install
sudo apt install pgbouncer -y

# Configure /etc/pgbouncer/pgbouncer.ini
[databases]
* = host=localhost port=5432

[pgbouncer]
listen_addr = *
listen_port = 6432
auth_type = md5
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
```

**Benefits:**
- Support 1000+ connections with only 25 actual PostgreSQL connections
- Reduce connection overhead
- Better resource utilization

## Monitoring After Deployment

### Essential Metrics to Watch

1. **CPU Usage**
```bash
htop
# Watch for: sustained >70% usage
```

2. **Memory Usage**
```bash
free -h
# Watch for: <20% free
```

3. **Disk I/O**
```bash
iostat -x 1
# Watch for: %util >80%
```

4. **PostgreSQL Stats**
```sql
-- Active connections per database
SELECT datname, count(*)
FROM pg_stat_activity
GROUP BY datname;

-- Database sizes
SELECT datname, pg_size_pretty(pg_database_size(datname))
FROM pg_database
ORDER BY pg_database_size(datname) DESC;

-- Slow queries (if logged)
SELECT * FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

5. **Connection Pool (if using PgBouncer)**
```bash
psql -p 6432 -U pgbouncer pgbouncer -c "SHOW POOLS;"
```

### Monitoring Tools (Recommended)

**Option 1: Prometheus + Grafana**
- Industry standard
- Beautiful dashboards
- Alerting

**Option 2: pgAdmin**
- Built-in PostgreSQL monitoring
- Good for small setups

**Option 3: Simple Scripts**
```bash
# Create monitoring script
cat > /usr/local/bin/pg-monitor << 'EOF'
#!/bin/bash
echo "=== PostgreSQL Status ==="
echo "Connections: $(psql -U postgres -t -c "SELECT count(*) FROM pg_stat_activity;")"
echo "Databases: $(psql -U postgres -t -c "SELECT count(*) FROM pg_database WHERE datistemplate = false;")"
echo "Total Size: $(psql -U postgres -t -c "SELECT pg_size_pretty(sum(pg_database_size(datname))::bigint) FROM pg_database;")"
echo ""
echo "=== System Resources ==="
echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')% used"
echo "Memory: $(free -h | awk '/^Mem:/{print $3 "/" $2}')"
echo "Disk: $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 " used)"}')"
EOF

chmod +x /usr/local/bin/pg-monitor

# Run anytime
pg-monitor
```

## When to Scale Up

Consider upgrading when:

1. **CPU** consistently >70% during business hours
2. **Memory** <20% free regularly
3. **Disk I/O** wait >15% consistently
4. **Queries** slowing down (check slow query log)
5. **Connections** approaching max_connections

## Troubleshooting

### Benchmark Script Fails

```bash
# Check disk space
df -h

# Check PostgreSQL is running
sudo systemctl status postgresql

# Check connection
psql -U postgres -c "SELECT 1;"

# View detailed errors
./benchmark-postgres.sh localhost 5432 postgres 2>&1 | tee debug.log
```

### Low Performance Results

1. **Check if other processes are running**
```bash
top
# Look for high CPU/memory usage
```

2. **Ensure PostgreSQL is properly configured**
```bash
# Check current settings
psql -U postgres -c "SHOW shared_buffers;"
psql -U postgres -c "SHOW max_connections;"
```

3. **Verify disk is SSD not HDD**
```bash
lsblk -d -o name,rota
# rota=0: SSD, rota=1: HDD
```

4. **Check system load**
```bash
uptime
# Load should be < number of CPU cores
```

## Next Steps After Benchmarking

1. **Review the complete report**
   ```bash
   cat benchmark-results-*/BENCHMARK-REPORT.txt
   ```

2. **Implement recommendations**
   - Adjust PostgreSQL configuration
   - Tune system parameters
   - Install PgBouncer if needed

3. **Set up monitoring**
   - Install monitoring tools
   - Create alerts for key metrics

4. **Test with real workload**
   - Deploy a few test databases
   - Monitor performance under load
   - Adjust based on actual usage

5. **Document your setup**
   - Save benchmark results
   - Document configuration changes
   - Track performance over time

## Summary

Your Ubuntu server at **94.130.137.39** is ready for benchmarking!

**To get started:**

```bash
# SSH into your server
ssh root@94.130.137.39

# Navigate to this directory
cd /path/to/postgres-as-service

# Run the comprehensive benchmark
sudo ./run-benchmarks.sh
```

The benchmark will take 5-10 minutes and provide:
- Detailed performance metrics
- Hosting capacity estimate
- Configuration recommendations
- Optimization suggestions

**Questions to answer:**
- ✓ Can this server handle multiple applications?
- ✓ How many databases can I host?
- ✓ What's the expected concurrent connection capacity?
- ✓ What optimizations should I make?
- ✓ When should I scale up?

All answers will be in your benchmark report!
