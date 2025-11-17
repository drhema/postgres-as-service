#!/bin/bash

# Server Performance Benchmark Script
# Tests CPU, Memory, Disk I/O, and Network performance

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

RESULTS_FILE="server-benchmark-$(date +%Y%m%d-%H%M%S).log"
TEMP_DIR="/tmp/benchmark_$$"

echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      Server Performance Benchmark Suite          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Results will be saved to: $RESULTS_FILE${NC}"
echo ""

# Function to print section headers
print_header() {
    echo "" | tee -a "$RESULTS_FILE"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$RESULTS_FILE"
    echo -e "${GREEN}$1${NC}" | tee -a "$RESULTS_FILE"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$RESULTS_FILE"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install missing tools
install_tools() {
    local missing_tools=()

    if ! command_exists sysbench; then
        missing_tools+=("sysbench")
    fi
    if ! command_exists hdparm; then
        missing_tools+=("hdparm")
    fi
    if ! command_exists iperf3; then
        missing_tools+=("iperf3")
    fi
    if ! command_exists fio; then
        missing_tools+=("fio")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${YELLOW}Installing required tools: ${missing_tools[*]}${NC}"
        apt-get update -qq
        apt-get install -y -qq sysbench hdparm iperf3 fio bc > /dev/null 2>&1
        echo -e "${GREEN}✓ Tools installed${NC}"
    fi
}

# Initialize results file
{
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║      Server Performance Benchmark Results         ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo ""
    echo "Date: $(date)"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
} > "$RESULTS_FILE"

# System Information
print_header "1. System Information"
{
    echo ""
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo ""
    echo "CPU Information:"
    echo "  Model: $(lscpu | grep "Model name" | cut -d':' -f2 | xargs)"
    echo "  Cores: $(nproc) cores"
    echo "  Threads: $(lscpu | grep "^CPU(s):" | awk '{print $2}')"
    echo "  Max MHz: $(lscpu | grep "CPU max MHz" | awk '{print $4}' || echo "N/A")"
    echo ""
    echo "Memory Information:"
    free -h | grep -E "Mem|Swap"
    echo ""
    echo "Disk Information:"
    df -h | grep -E "^/dev|Filesystem"
} | tee -a "$RESULTS_FILE"

# Check and install tools
print_header "2. Checking Required Tools"
install_tools

# Create temp directory
mkdir -p "$TEMP_DIR"

# CPU Performance Tests
print_header "3. CPU Performance"

echo -e "${YELLOW}Testing: CPU single-thread performance${NC}" | tee -a "$RESULTS_FILE"
echo "Running prime number calculation (single thread)..." | tee -a "$RESULTS_FILE"
cpu_single=$(sysbench cpu --cpu-max-prime=20000 --threads=1 run 2>/dev/null | grep "events per second" | awk '{print $4}')
echo -e "  ${GREEN}✓${NC} Single-thread: ${cpu_single} events/sec" | tee -a "$RESULTS_FILE"

echo -e "${YELLOW}Testing: CPU multi-thread performance${NC}" | tee -a "$RESULTS_FILE"
threads=$(nproc)
echo "Running prime number calculation ($threads threads)..." | tee -a "$RESULTS_FILE"
cpu_multi=$(sysbench cpu --cpu-max-prime=20000 --threads=$threads run 2>/dev/null | grep "events per second" | awk '{print $4}')
echo -e "  ${GREEN}✓${NC} Multi-thread ($threads cores): ${cpu_multi} events/sec" | tee -a "$RESULTS_FILE"

scaling=$(echo "scale=2; $cpu_multi / $cpu_single" | bc)
echo -e "  ${CYAN}Scaling efficiency: ${scaling}x${NC}" | tee -a "$RESULTS_FILE"

# Memory Performance Tests
print_header "4. Memory Performance"

echo -e "${YELLOW}Testing: Memory read/write speed${NC}" | tee -a "$RESULTS_FILE"
echo "Running memory benchmark..." | tee -a "$RESULTS_FILE"
mem_result=$(sysbench memory --memory-block-size=1M --memory-total-size=10G run 2>/dev/null)
mem_throughput=$(echo "$mem_result" | grep "transferred" | awk '{print $(NF-1), $NF}')
mem_latency=$(echo "$mem_result" | grep "total time:" | awk '{print $3}')
echo -e "  ${GREEN}✓${NC} Throughput: ${mem_throughput}" | tee -a "$RESULTS_FILE"
echo -e "  ${GREEN}✓${NC} Latency: ${mem_latency}" | tee -a "$RESULTS_FILE"

echo -e "${YELLOW}Testing: Memory allocation speed${NC}" | tee -a "$RESULTS_FILE"
start_time=$(date +%s.%N)
sysbench memory --memory-oper=write --memory-block-size=1K --memory-total-size=1G run > /dev/null 2>&1
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
echo -e "  ${GREEN}✓${NC} 1GB allocation: ${duration}s" | tee -a "$RESULTS_FILE"

# Disk I/O Performance Tests
print_header "5. Disk I/O Performance"

# Find the main disk device
DISK_DEVICE=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')
echo "Testing disk: $DISK_DEVICE" | tee -a "$RESULTS_FILE"
echo ""

echo -e "${YELLOW}Testing: Sequential read performance${NC}" | tee -a "$RESULTS_FILE"
if [ -b "$DISK_DEVICE" ]; then
    read_speed=$(hdparm -t "$DISK_DEVICE" 2>/dev/null | grep "Timing buffered disk reads" | awk '{print $(NF-1), $NF}' || echo "N/A")
    echo -e "  ${GREEN}✓${NC} Sequential read: ${read_speed}" | tee -a "$RESULTS_FILE"
else
    echo -e "  ${YELLOW}⚠${NC} Cannot test raw device, using file-based test" | tee -a "$RESULTS_FILE"
fi

echo -e "${YELLOW}Testing: Random I/O with FIO${NC}" | tee -a "$RESULTS_FILE"
echo "Running 4K random read test..." | tee -a "$RESULTS_FILE"
fio --name=randread --ioengine=libaio --iodepth=16 --rw=randread --bs=4k --direct=1 \
    --size=1G --numjobs=4 --runtime=30 --group_reporting \
    --filename="$TEMP_DIR/test_randread" 2>/dev/null | \
    grep -E "read:|IOPS" | head -2 | tee -a "$RESULTS_FILE"

echo ""
echo "Running 4K random write test..." | tee -a "$RESULTS_FILE"
fio --name=randwrite --ioengine=libaio --iodepth=16 --rw=randwrite --bs=4k --direct=1 \
    --size=1G --numjobs=4 --runtime=30 --group_reporting \
    --filename="$TEMP_DIR/test_randwrite" 2>/dev/null | \
    grep -E "write:|IOPS" | head -2 | tee -a "$RESULTS_FILE"

echo ""
echo "Running sequential write test (1GB file)..." | tee -a "$RESULTS_FILE"
sync; dd if=/dev/zero of="$TEMP_DIR/testfile" bs=1M count=1024 oflag=direct 2>&1 | \
    grep -E "copied|MB/s" | tee -a "$RESULTS_FILE"

echo ""
echo "Running sequential read test (1GB file)..." | tee -a "$RESULTS_FILE"
sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
dd if="$TEMP_DIR/testfile" of=/dev/null bs=1M 2>&1 | \
    grep -E "copied|MB/s" | tee -a "$RESULTS_FILE"

# File System Performance
print_header "6. File System Performance"

echo -e "${YELLOW}Testing: Small file operations${NC}" | tee -a "$RESULTS_FILE"
echo "Creating 10,000 small files..." | tee -a "$RESULTS_FILE"
start_time=$(date +%s.%N)
mkdir -p "$TEMP_DIR/small_files"
for i in {1..10000}; do
    echo "test" > "$TEMP_DIR/small_files/file_$i.txt"
done
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
files_per_sec=$(echo "scale=2; 10000 / $duration" | bc)
echo -e "  ${GREEN}✓${NC} Created 10,000 files in ${duration}s (${files_per_sec} files/sec)" | tee -a "$RESULTS_FILE"

echo -e "${YELLOW}Testing: File deletion performance${NC}" | tee -a "$RESULTS_FILE"
start_time=$(date +%s.%N)
rm -rf "$TEMP_DIR/small_files"
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)
echo -e "  ${GREEN}✓${NC} Deleted 10,000 files in ${duration}s" | tee -a "$RESULTS_FILE"

# Network Performance Tests
print_header "7. Network Performance"

echo -e "${YELLOW}Testing: Network interface information${NC}" | tee -a "$RESULTS_FILE"
{
    echo ""
    ip -brief addr show | grep -v "lo"
    echo ""
    echo "Network Statistics:"
    netstat -i | grep -v "Kernel\|Iface\|lo"
} | tee -a "$RESULTS_FILE"

echo ""
echo -e "${YELLOW}Testing: External network speed (speedtest)${NC}" | tee -a "$RESULTS_FILE"
if command_exists curl; then
    echo "Testing download speed from internet..." | tee -a "$RESULTS_FILE"
    start_time=$(date +%s.%N)
    curl -s -o /dev/null -w "  Download speed: %{speed_download} bytes/sec\n" \
        https://speedtest.tele2.net/10MB.zip 2>/dev/null | tee -a "$RESULTS_FILE"

    download_mbps=$(curl -s -o /dev/null -w "%{speed_download}" \
        https://speedtest.tele2.net/10MB.zip 2>/dev/null | \
        awk '{printf "%.2f", $1/1024/1024}')
    echo -e "  ${GREEN}✓${NC} Download: ${download_mbps} MB/s" | tee -a "$RESULTS_FILE"
else
    echo -e "  ${YELLOW}⚠${NC} curl not available, skipping network test" | tee -a "$RESULTS_FILE"
fi

# Database-specific tests
print_header "8. System Limits & Configuration"
{
    echo ""
    echo "Open file limits:"
    ulimit -n
    echo ""
    echo "Max processes:"
    ulimit -u
    echo ""
    echo "Virtual memory settings:"
    sysctl vm.swappiness 2>/dev/null || echo "vm.swappiness: N/A"
    sysctl vm.overcommit_memory 2>/dev/null || echo "vm.overcommit_memory: N/A"
    echo ""
    echo "TCP settings:"
    sysctl net.ipv4.tcp_max_syn_backlog 2>/dev/null || echo "tcp_max_syn_backlog: N/A"
    sysctl net.core.somaxconn 2>/dev/null || echo "somaxconn: N/A"
} | tee -a "$RESULTS_FILE"

# Load Average
print_header "9. System Load"
{
    echo ""
    echo "Current load average:"
    uptime
    echo ""
    echo "Top 5 processes by CPU:"
    ps aux --sort=-%cpu | head -6
    echo ""
    echo "Top 5 processes by Memory:"
    ps aux --sort=-%mem | head -6
} | tee -a "$RESULTS_FILE"

# Cleanup
print_header "10. Cleanup"
echo -e "${YELLOW}Removing temporary files${NC}" | tee -a "$RESULTS_FILE"
rm -rf "$TEMP_DIR"
echo -e "${GREEN}✓ Cleanup complete${NC}" | tee -a "$RESULTS_FILE"

# Performance Summary
print_header "11. Performance Summary & Recommendations"
{
    echo ""
    echo "CPU Performance:"
    echo "  Single-thread: $cpu_single events/sec"
    echo "  Multi-thread: $cpu_multi events/sec"
    echo "  Scaling: ${scaling}x"

    # Recommendations based on CPU
    if (( $(echo "$cpu_single < 1000" | bc -l) )); then
        echo "  ⚠ WARNING: Low single-thread performance. May struggle with complex queries."
    elif (( $(echo "$cpu_single > 2000" | bc -l) )); then
        echo "  ✓ Good single-thread performance for database workloads."
    fi

    if (( $(echo "$scaling < $(nproc) * 0.7" | bc -l) )); then
        echo "  ⚠ WARNING: Poor multi-core scaling. Check CPU pinning and NUMA settings."
    fi

    echo ""
    echo "Memory:"
    total_mem=$(free -g | awk '/^Mem:/{print $2}')
    echo "  Total: ${total_mem}GB"

    if [ "$total_mem" -lt 4 ]; then
        echo "  ⚠ WARNING: Low memory. Recommended minimum 8GB for database hosting."
    elif [ "$total_mem" -lt 8 ]; then
        echo "  ⚠ Adequate for small workloads. Consider 16GB+ for production."
    else
        echo "  ✓ Good memory capacity for database hosting."
    fi

    echo ""
    echo "Storage:"
    echo "  Type: $(lsblk -d -o name,rota | tail -1 | awk '{if($2==0) print "SSD"; else print "HDD"}')"

    echo ""
    echo "Recommendations:"
    echo "  1. For PostgreSQL multi-tenant:"
    echo "     • Recommended: 4+ CPU cores, 8GB+ RAM, SSD storage"
    echo "     • Optimal: 8+ CPU cores, 16GB+ RAM, NVMe SSD"
    echo ""
    echo "  2. System tuning:"
    echo "     • Set vm.swappiness=10 for database workloads"
    echo "     • Increase max_connections and shared_buffers in PostgreSQL"
    echo "     • Consider connection pooler (PgBouncer) for high concurrency"
    echo ""
    echo "  3. Expected capacity (rough estimates):"
    cores=$(nproc)
    if [ "$cores" -ge 8 ] && [ "$total_mem" -ge 16 ]; then
        echo "     • 50-100 small databases (< 1GB each)"
        echo "     • 1000-2000 concurrent connections (with pooling)"
        echo "     • Good for production multi-tenant SaaS"
    elif [ "$cores" -ge 4 ] && [ "$total_mem" -ge 8 ]; then
        echo "     • 20-50 small databases"
        echo "     • 500-1000 concurrent connections (with pooling)"
        echo "     • Good for small to medium workloads"
    else
        echo "     • 5-20 small databases"
        echo "     • 100-500 concurrent connections (with pooling)"
        echo "     • Suitable for development/testing"
    fi
} | tee -a "$RESULTS_FILE"

echo "" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}║              Benchmark Complete                   ║${NC}" | tee -a "$RESULTS_FILE"
echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"
echo -e "${GREEN}Results saved to: $RESULTS_FILE${NC}"
echo ""
