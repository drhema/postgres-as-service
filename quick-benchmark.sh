#!/bin/bash

# Quick Benchmark - Simplified version for remote execution
# Usage: curl -sSL [URL] | sudo bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Quick Server & PostgreSQL Benchmark          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root: sudo $0${NC}"
    exit 1
fi

# Install required tools
echo -e "${YELLOW}Installing benchmark tools...${NC}"
apt-get update -qq
apt-get install -y -qq sysbench postgresql-client bc curl > /dev/null 2>&1
echo -e "${GREEN}✓ Tools installed${NC}"
echo ""

# Server quick check
echo -e "${YELLOW}=== Server Quick Check ===${NC}"
echo "CPU: $(nproc) cores - $(lscpu | grep "Model name" | cut -d':' -f2 | xargs)"
echo "RAM: $(free -h | awk '/^Mem:/{print $2}')"
echo "Disk: $(df -h / | awk 'NR==2{print $2}') ($(lsblk -d -o name,rota | tail -1 | awk '{if($2==0) print "SSD"; else print "HDD"}'))"
echo ""

# Quick CPU test
echo -e "${YELLOW}Testing CPU...${NC}"
cpu_score=$(sysbench cpu --cpu-max-prime=10000 --threads=$(nproc) run 2>/dev/null | grep "events per second" | awk '{print $4}')
echo -e "${GREEN}✓ CPU Score: $cpu_score events/sec${NC}"
echo ""

# Quick disk test
echo -e "${YELLOW}Testing Disk I/O...${NC}"
dd_result=$(dd if=/dev/zero of=/tmp/test bs=1M count=512 oflag=direct 2>&1 | grep -o '[0-9.]* MB/s')
rm -f /tmp/test
echo -e "${GREEN}✓ Disk Write: $dd_result${NC}"
echo ""

# PostgreSQL check
echo -e "${YELLOW}Checking PostgreSQL...${NC}"
if systemctl is-active --quiet postgresql; then
    echo -e "${GREEN}✓ PostgreSQL is running${NC}"
    pg_version=$(sudo -u postgres psql -t -c "SELECT version();" 2>/dev/null | head -1 | xargs)
    echo "  Version: $pg_version"
else
    echo -e "${RED}✗ PostgreSQL is not running${NC}"
fi
echo ""

# Capacity estimate
cores=$(nproc)
ram_gb=$(free -g | awk '/^Mem:/{print $2}')

echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Quick Capacity Estimate                ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$cores" -ge 8 ] && [ "$ram_gb" -ge 16 ]; then
    echo -e "${GREEN}Rating: EXCELLENT${NC}"
    echo "Estimated: 50-100 databases, 1000-2000 connections"
elif [ "$cores" -ge 4 ] && [ "$ram_gb" -ge 8 ]; then
    echo -e "${GREEN}Rating: GOOD${NC}"
    echo "Estimated: 20-50 databases, 500-1000 connections"
elif [ "$cores" -ge 2 ] && [ "$ram_gb" -ge 4 ]; then
    echo -e "${YELLOW}Rating: FAIR${NC}"
    echo "Estimated: 10-20 databases, 200-500 connections"
else
    echo -e "${RED}Rating: LIMITED${NC}"
    echo "Estimated: 5-10 databases, 50-200 connections"
fi

echo ""
echo -e "${CYAN}For detailed benchmarks, run the full benchmark suite.${NC}"
echo ""
