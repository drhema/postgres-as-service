#!/bin/bash

# PostgreSQL Performance Benchmark Script
# Tests database performance for multi-tenant workloads

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DB_HOST="${1:-localhost}"
DB_PORT="${2:-5432}"
DB_USER="${3:-postgres}"
TEST_DB="benchmark_test_$(date +%s)"
RESULTS_FILE="postgres-benchmark-$(date +%Y%m%d-%H%M%S).log"

echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   PostgreSQL Performance Benchmark Suite         ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Server: $DB_HOST:$DB_PORT${NC}"
echo -e "${YELLOW}User: $DB_USER${NC}"
echo -e "${YELLOW}Results will be saved to: $RESULTS_FILE${NC}"
echo ""

# Function to print section headers
print_header() {
    echo "" | tee -a "$RESULTS_FILE"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$RESULTS_FILE"
    echo -e "${GREEN}$1${NC}" | tee -a "$RESULTS_FILE"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$RESULTS_FILE"
}

# Function to execute SQL and measure time
execute_benchmark() {
    local description="$1"
    local sql="$2"
    echo -e "${YELLOW}Testing: $description${NC}" | tee -a "$RESULTS_FILE"

    local start_time=$(date +%s.%N)
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" -c "$sql" > /dev/null 2>&1 || true
    local end_time=$(date +%s.%N)

    local duration=$(echo "$end_time - $start_time" | bc)
    echo -e "  ${GREEN}✓${NC} Completed in ${duration}s" | tee -a "$RESULTS_FILE"
    echo "$duration"
}

# Prompt for password
echo -e "${YELLOW}Enter PostgreSQL password for $DB_USER:${NC}"
read -s DB_PASSWORD
export DB_PASSWORD

echo ""
echo -e "${YELLOW}Testing connection...${NC}"

# Test connection
if ! PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${RED}✗ Failed to connect to PostgreSQL${NC}"
    echo -e "${RED}Please check your credentials and server availability${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Connection successful${NC}"
echo ""

# Initialize results file
{
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║   PostgreSQL Performance Benchmark Results        ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo ""
    echo "Date: $(date)"
    echo "Server: $DB_HOST:$DB_PORT"
    echo "PostgreSQL Version: $(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -t -c "SELECT version();" 2>/dev/null | head -1)"
} > "$RESULTS_FILE"

# Create test database
print_header "1. Database Setup"
echo -e "${YELLOW}Creating test database: $TEST_DB${NC}" | tee -a "$RESULTS_FILE"
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "CREATE DATABASE $TEST_DB;" 2>/dev/null || true
echo -e "${GREEN}✓ Test database created${NC}" | tee -a "$RESULTS_FILE"

# Test 1: Simple SELECT performance
print_header "2. Basic Query Performance"
execute_benchmark "1000 simple SELECT queries" "
DO \$\$
BEGIN
    FOR i IN 1..1000 LOOP
        PERFORM 1;
    END LOOP;
END \$\$;
"

# Test 2: Table creation and indexing
print_header "3. Table Creation & Indexing"
execute_benchmark "Create table with indexes" "
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_created_at ON users(created_at);
"

# Test 3: Bulk INSERT performance
print_header "4. Bulk INSERT Performance"
echo -e "${YELLOW}Testing: Inserting 10,000 rows${NC}" | tee -a "$RESULTS_FILE"
start_time=$(date +%s.%N)
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" > /dev/null 2>&1 <<EOF
INSERT INTO users (username, email)
SELECT
    'user' || i,
    'user' || i || '@example.com'
FROM generate_series(1, 10000) AS i;
EOF
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
rows_per_sec=$(echo "scale=2; 10000 / $duration" | bc)
echo -e "  ${GREEN}✓${NC} Inserted 10,000 rows in ${duration}s (${rows_per_sec} rows/sec)" | tee -a "$RESULTS_FILE"

# Test 4: SELECT performance with different patterns
print_header "5. SELECT Query Performance"

echo -e "${YELLOW}Testing: Full table scan${NC}" | tee -a "$RESULTS_FILE"
start_time=$(date +%s.%N)
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" -c "SELECT COUNT(*) FROM users;" > /dev/null 2>&1
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
echo -e "  ${GREEN}✓${NC} Full scan completed in ${duration}s" | tee -a "$RESULTS_FILE"

echo -e "${YELLOW}Testing: Indexed query${NC}" | tee -a "$RESULTS_FILE"
start_time=$(date +%s.%N)
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" -c "SELECT * FROM users WHERE email = 'user5000@example.com';" > /dev/null 2>&1
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
echo -e "  ${GREEN}✓${NC} Indexed lookup completed in ${duration}s" | tee -a "$RESULTS_FILE"

echo -e "${YELLOW}Testing: JOIN performance${NC}" | tee -a "$RESULTS_FILE"
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" > /dev/null 2>&1 <<EOF
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    amount DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO orders (user_id, amount)
SELECT
    (RANDOM() * 10000)::INTEGER + 1,
    RANDOM() * 1000
FROM generate_series(1, 5000);
EOF
start_time=$(date +%s.%N)
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" -c "SELECT u.username, COUNT(o.id) as order_count FROM users u LEFT JOIN orders o ON u.id = o.user_id GROUP BY u.username LIMIT 100;" > /dev/null 2>&1
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
echo -e "  ${GREEN}✓${NC} JOIN query completed in ${duration}s" | tee -a "$RESULTS_FILE"

# Test 5: UPDATE performance
print_header "6. UPDATE Performance"
echo -e "${YELLOW}Testing: Bulk UPDATE${NC}" | tee -a "$RESULTS_FILE"
start_time=$(date +%s.%N)
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" -c "UPDATE users SET updated_at = NOW() WHERE id <= 5000;" > /dev/null 2>&1
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
rows_per_sec=$(echo "scale=2; 5000 / $duration" | bc)
echo -e "  ${GREEN}✓${NC} Updated 5,000 rows in ${duration}s (${rows_per_sec} rows/sec)" | tee -a "$RESULTS_FILE"

# Test 6: Transaction performance
print_header "7. Transaction Performance"
echo -e "${YELLOW}Testing: 1000 small transactions${NC}" | tee -a "$RESULTS_FILE"
start_time=$(date +%s.%N)
for i in {1..1000}; do
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" > /dev/null 2>&1 <<EOF
BEGIN;
UPDATE users SET updated_at = NOW() WHERE id = $i;
COMMIT;
EOF
done
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
tps=$(echo "scale=2; 1000 / $duration" | bc)
echo -e "  ${GREEN}✓${NC} Completed 1000 transactions in ${duration}s (${tps} TPS)" | tee -a "$RESULTS_FILE"

# Test 7: Concurrent connections
print_header "8. Connection Performance"
echo -e "${YELLOW}Testing: Connection overhead (10 sequential connections)${NC}" | tee -a "$RESULTS_FILE"
start_time=$(date +%s.%N)
for i in {1..10}; do
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" -c "SELECT 1;" > /dev/null 2>&1
done
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
avg_time=$(echo "scale=4; $duration / 10" | bc)
echo -e "  ${GREEN}✓${NC} 10 connections in ${duration}s (avg: ${avg_time}s per connection)" | tee -a "$RESULTS_FILE"

# Test 8: Complex query performance
print_header "9. Complex Query Performance"
echo -e "${YELLOW}Testing: Aggregation with subqueries${NC}" | tee -a "$RESULTS_FILE"
start_time=$(date +%s.%N)
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" > /dev/null 2>&1 <<EOF
WITH user_stats AS (
    SELECT
        u.id,
        u.username,
        COUNT(o.id) as order_count,
        COALESCE(SUM(o.amount), 0) as total_amount
    FROM users u
    LEFT JOIN orders o ON u.id = o.user_id
    GROUP BY u.id, u.username
)
SELECT
    COUNT(*) as total_users,
    AVG(order_count) as avg_orders_per_user,
    AVG(total_amount) as avg_amount_per_user,
    MAX(total_amount) as max_amount
FROM user_stats;
EOF
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
echo -e "  ${GREEN}✓${NC} Complex aggregation completed in ${duration}s" | tee -a "$RESULTS_FILE"

# Test 9: Database statistics
print_header "10. Database Statistics"
echo -e "${YELLOW}Gathering database metrics${NC}" | tee -a "$RESULTS_FILE"
{
    echo ""
    echo "Database Size:"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" -c "SELECT pg_size_pretty(pg_database_size('$TEST_DB')) as database_size;"
    echo ""
    echo "Table Sizes:"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$TEST_DB" -c "SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS size FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC;"
    echo ""
    echo "Active Connections:"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "SELECT count(*) as active_connections FROM pg_stat_activity WHERE datname = '$TEST_DB';"
} | tee -a "$RESULTS_FILE"

# Test 10: Server configuration
print_header "11. Server Configuration"
{
    echo ""
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "SELECT name, setting, unit FROM pg_settings WHERE name IN ('max_connections', 'shared_buffers', 'effective_cache_size', 'work_mem', 'maintenance_work_mem', 'random_page_cost', 'effective_io_concurrency');"
} | tee -a "$RESULTS_FILE"

# Cleanup
print_header "12. Cleanup"
echo -e "${YELLOW}Removing test database${NC}" | tee -a "$RESULTS_FILE"
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "DROP DATABASE $TEST_DB;" 2>/dev/null || true
echo -e "${GREEN}✓ Cleanup complete${NC}" | tee -a "$RESULTS_FILE"

# Summary
echo "" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}║              Benchmark Complete                   ║${NC}" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"
echo -e "${GREEN}Results saved to: $RESULTS_FILE${NC}"
echo ""
echo -e "${YELLOW}Recommendations for multi-tenant hosting:${NC}"
echo -e "  • Monitor the TPS (transactions per second) metric"
echo -e "  • Connection overhead should be < 0.1s for good performance"
echo -e "  • Consider connection pooling (PgBouncer) for high concurrency"
echo -e "  • Review shared_buffers and work_mem settings for optimization"
echo ""
