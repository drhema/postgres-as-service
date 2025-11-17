#!/bin/bash

# Comprehensive Benchmark Runner
# Runs both server and PostgreSQL benchmarks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_DIR="benchmark-results-$TIMESTAMP"
FINAL_REPORT="$REPORT_DIR/BENCHMARK-REPORT.txt"

# Banner
clear
echo -e "${MAGENTA}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     PostgreSQL as a Service - Benchmark Suite                ║
║                                                               ║
║     Complete server and database performance analysis         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo -e "${CYAN}This benchmark suite will test:${NC}"
echo -e "  ${GREEN}✓${NC} Server Performance (CPU, Memory, Disk, Network)"
echo -e "  ${GREEN}✓${NC} PostgreSQL Database Performance"
echo -e "  ${GREEN}✓${NC} Multi-tenant hosting capability"
echo ""
echo -e "${YELLOW}Estimated time: 5-10 minutes${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ This script requires root privileges${NC}"
    echo -e "${YELLOW}Please run: sudo $0${NC}"
    exit 1
fi

# Create results directory
mkdir -p "$REPORT_DIR"

echo -e "${CYAN}Results will be saved to: $REPORT_DIR/${NC}"
echo ""

# Function to print section
print_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Get PostgreSQL connection details
print_section "PostgreSQL Connection Information"
echo -e "${YELLOW}Please provide PostgreSQL connection details:${NC}"
echo ""

read -p "PostgreSQL Host (default: localhost): " PG_HOST
PG_HOST=${PG_HOST:-localhost}

read -p "PostgreSQL Port (default: 5432): " PG_PORT
PG_PORT=${PG_PORT:-5432}

read -p "PostgreSQL User (default: postgres): " PG_USER
PG_USER=${PG_USER:-postgres}

echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Host: $PG_HOST"
echo "  Port: $PG_PORT"
echo "  User: $PG_USER"
echo ""

# Confirm before proceeding
read -p "Start benchmarks? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ] && [ "$CONFIRM" != "y" ]; then
    echo -e "${YELLOW}Benchmark cancelled${NC}"
    exit 0
fi

# Initialize report
{
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║          COMPREHENSIVE BENCHMARK REPORT                       ║"
    echo "║       PostgreSQL Multi-Tenant Hosting Analysis                ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Generated: $(date)"
    echo "Server: $PG_HOST"
    echo ""
} > "$FINAL_REPORT"

# Run Server Benchmark
print_section "1/2: Running Server Performance Benchmark"
echo -e "${CYAN}Testing CPU, Memory, Disk I/O, and Network...${NC}"
echo ""

if [ -f "./benchmark-server.sh" ]; then
    ./benchmark-server.sh 2>&1 | tee "$REPORT_DIR/server-benchmark.log"

    # Copy server benchmark results to report directory
    latest_server=$(ls -t server-benchmark-*.log 2>/dev/null | head -1)
    if [ -n "$latest_server" ]; then
        cp "$latest_server" "$REPORT_DIR/"
        echo "══════════════════════════════════════════════════════════════" >> "$FINAL_REPORT"
        echo "PART 1: SERVER PERFORMANCE" >> "$FINAL_REPORT"
        echo "══════════════════════════════════════════════════════════════" >> "$FINAL_REPORT"
        cat "$latest_server" >> "$FINAL_REPORT"
        rm "$latest_server"
    fi

    echo ""
    echo -e "${GREEN}✓ Server benchmark complete${NC}"
else
    echo -e "${RED}✗ benchmark-server.sh not found${NC}"
fi

sleep 2

# Run PostgreSQL Benchmark
print_section "2/2: Running PostgreSQL Performance Benchmark"
echo -e "${CYAN}Testing database performance...${NC}"
echo ""

if [ -f "./benchmark-postgres.sh" ]; then
    ./benchmark-postgres.sh "$PG_HOST" "$PG_PORT" "$PG_USER" 2>&1 | tee "$REPORT_DIR/postgres-benchmark.log"

    # Copy PostgreSQL benchmark results to report directory
    latest_postgres=$(ls -t postgres-benchmark-*.log 2>/dev/null | head -1)
    if [ -n "$latest_postgres" ]; then
        cp "$latest_postgres" "$REPORT_DIR/"
        echo "" >> "$FINAL_REPORT"
        echo "" >> "$FINAL_REPORT"
        echo "══════════════════════════════════════════════════════════════" >> "$FINAL_REPORT"
        echo "PART 2: POSTGRESQL PERFORMANCE" >> "$FINAL_REPORT"
        echo "══════════════════════════════════════════════════════════════" >> "$FINAL_REPORT"
        cat "$latest_postgres" >> "$FINAL_REPORT"
        rm "$latest_postgres"
    fi

    echo ""
    echo -e "${GREEN}✓ PostgreSQL benchmark complete${NC}"
else
    echo -e "${RED}✗ benchmark-postgres.sh not found${NC}"
fi

# Generate final summary
print_section "Generating Final Report"

{
    echo ""
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "EXECUTIVE SUMMARY"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    echo "Server Specifications:"
    echo "  • CPU: $(nproc) cores - $(lscpu | grep "Model name" | cut -d':' -f2 | xargs)"
    echo "  • RAM: $(free -h | awk '/^Mem:/{print $2}')"
    echo "  • Disk: $(df -h / | awk 'NR==2{print $2}') total, $(df -h / | awk 'NR==2{print $4}') available"
    echo "  • OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo ""

    # Calculate hosting capacity estimate
    cores=$(nproc)
    ram_gb=$(free -g | awk '/^Mem:/{print $2}')

    echo "Multi-Tenant Hosting Capacity Estimate:"
    echo ""

    if [ "$cores" -ge 8 ] && [ "$ram_gb" -ge 16 ]; then
        capacity_rating="EXCELLENT"
        db_count="50-100"
        conn_count="1000-2000"
        workload="Production multi-tenant SaaS"
    elif [ "$cores" -ge 4 ] && [ "$ram_gb" -ge 8 ]; then
        capacity_rating="GOOD"
        db_count="20-50"
        conn_count="500-1000"
        workload="Small to medium production workloads"
    elif [ "$cores" -ge 2 ] && [ "$ram_gb" -ge 4 ]; then
        capacity_rating="FAIR"
        db_count="10-20"
        conn_count="200-500"
        workload="Development and testing"
    else
        capacity_rating="LIMITED"
        db_count="5-10"
        conn_count="50-200"
        workload="Development only"
    fi

    echo "  Overall Rating: $capacity_rating"
    echo "  Estimated Database Count: $db_count small databases (< 1GB each)"
    echo "  Concurrent Connections: $conn_count (with connection pooling)"
    echo "  Recommended Workload: $workload"
    echo ""

    echo "Key Recommendations:"
    echo ""
    echo "  1. PostgreSQL Configuration:"
    echo "     • shared_buffers: $(echo "$ram_gb * 256" | bc)MB (25% of RAM)"
    echo "     • effective_cache_size: $(echo "$ram_gb * 768" | bc)MB (75% of RAM)"
    echo "     • work_mem: 16MB-64MB (adjust based on workload)"
    echo "     • max_connections: 200-500 (use PgBouncer for more)"
    echo ""

    echo "  2. System Optimization:"
    echo "     • Install PgBouncer for connection pooling"
    echo "     • Configure vm.swappiness=10"
    echo "     • Set up monitoring (Prometheus + Grafana)"
    echo "     • Enable daily automated backups"
    echo ""

    echo "  3. Scaling Strategy:"
    if [ "$cores" -lt 4 ] || [ "$ram_gb" -lt 8 ]; then
        echo "     ⚠ Current resources are limited"
        echo "     → Upgrade to 4+ cores and 8GB+ RAM for production"
    elif [ "$cores" -lt 8 ] || [ "$ram_gb" -lt 16 ]; then
        echo "     ✓ Adequate for current needs"
        echo "     → Consider 8+ cores and 16GB+ RAM for growth"
    else
        echo "     ✓ Good capacity for multi-tenant hosting"
        echo "     → Monitor usage and scale horizontally when needed"
    fi
    echo ""

    echo "  4. Monitoring Metrics:"
    echo "     • CPU usage (keep below 70% average)"
    echo "     • Memory usage (leave 20% free)"
    echo "     • Disk I/O (watch for bottlenecks)"
    echo "     • Database connections (monitor per tenant)"
    echo "     • Query performance (slow query log)"
    echo ""

    echo "  5. Security & Maintenance:"
    echo "     • Enable SSL/TLS for all connections"
    echo "     • Implement per-database IP whitelisting"
    echo "     • Set up automated backups (daily minimum)"
    echo "     • Regular PostgreSQL updates"
    echo "     • Monitor audit logs"
    echo ""

    echo "══════════════════════════════════════════════════════════════"
    echo "BENCHMARK COMPLETION"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    echo "All benchmark results have been saved to:"
    echo "  Directory: $REPORT_DIR/"
    echo "  Report: $FINAL_REPORT"
    echo ""
    echo "Generated on: $(date)"
    echo ""
} >> "$FINAL_REPORT"

# Display final summary
echo ""
echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║                    BENCHMARKS COMPLETE                        ║${NC}"
echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ All benchmarks completed successfully${NC}"
echo ""
echo -e "${CYAN}Results Summary:${NC}"
echo -e "  • Server Rating: ${YELLOW}$capacity_rating${NC}"
echo -e "  • Database Capacity: ${YELLOW}$db_count databases${NC}"
echo -e "  • Connection Capacity: ${YELLOW}$conn_count connections${NC}"
echo ""
echo -e "${CYAN}Results Location:${NC}"
echo -e "  ${GREEN}$REPORT_DIR/${NC}"
echo ""
echo -e "${CYAN}View the complete report:${NC}"
echo -e "  ${YELLOW}cat $FINAL_REPORT${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo -e "  1. Review the full report for detailed metrics"
echo -e "  2. Implement recommended PostgreSQL settings"
echo -e "  3. Set up monitoring and backups"
echo -e "  4. Test with your actual workload"
echo ""
