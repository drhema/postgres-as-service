#!/bin/bash

#==============================================================================
# PostgreSQL Multi-Tenant SaaS - Complete Uninstall Script
#==============================================================================
# This script completely removes PostgreSQL, PgBouncer, and all configurations
# WARNING: This will DELETE ALL DATABASES and data!
#==============================================================================

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    echo "Please run: sudo $0"
    exit 1
  fi
}

show_banner() {
  echo -e "${RED}"
  cat << "BANNER"
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║           PostgreSQL Multi-Tenant SaaS UNINSTALLER            ║
║                                                                ║
║                    ⚠️  WARNING WARNING ⚠️                      ║
║                                                                ║
║  This will PERMANENTLY DELETE all PostgreSQL databases,       ║
║  configurations, and data on this server!                     ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
BANNER
  echo -e "${NC}"
}

# Confirm uninstallation
confirm_uninstall() {
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}                    ⚠️  FINAL WARNING ⚠️${NC}"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "This will remove:"
  echo "  • PostgreSQL 16 and all databases"
  echo "  • PgBouncer connection pooler"
  echo "  • All configurations in /etc/postgresql and /etc/pgbouncer"
  echo "  • All data in /var/lib/postgresql"
  echo "  • All logs and backups"
  echo "  • SSL certificates for PostgreSQL"
  echo ""
  echo -e "${YELLOW}Type 'DELETE EVERYTHING' (all caps) to proceed:${NC}"
  read -r confirmation

  if [[ "$confirmation" != "DELETE EVERYTHING" ]]; then
    log_warn "Uninstallation cancelled"
    exit 0
  fi
}

# Stop services
stop_services() {
  log_info "Stopping PostgreSQL and PgBouncer services..."

  # Stop PgBouncer
  if systemctl is-active --quiet pgbouncer 2>/dev/null; then
    systemctl stop pgbouncer
    log_success "PgBouncer stopped"
  fi

  # Stop PostgreSQL
  if systemctl is-active --quiet postgresql 2>/dev/null; then
    systemctl stop postgresql
    log_success "PostgreSQL stopped"
  fi

  sleep 2
}

# Remove packages
remove_packages() {
  log_info "Removing PostgreSQL and PgBouncer packages..."

  # Remove PgBouncer
  apt-get remove --purge -y pgbouncer 2>/dev/null || true

  # Remove PostgreSQL
  apt-get remove --purge -y postgresql-16 postgresql-client-16 postgresql-contrib-16 2>/dev/null || true
  apt-get remove --purge -y postgresql postgresql-client postgresql-contrib 2>/dev/null || true

  # Remove PostgreSQL repository
  rm -f /etc/apt/sources.list.d/pgdg.list
  rm -f /usr/share/keyrings/postgresql-archive-keyring.gpg

  # Clean up
  apt-get autoremove -y
  apt-get autoclean

  log_success "Packages removed"
}

# Remove configurations
remove_configurations() {
  log_info "Removing configuration directories..."

  # Remove PostgreSQL config
  if [[ -d /etc/postgresql ]]; then
    rm -rf /etc/postgresql
    log_success "Removed /etc/postgresql"
  fi

  # Remove PgBouncer config
  if [[ -d /etc/pgbouncer ]]; then
    rm -rf /etc/pgbouncer
    log_success "Removed /etc/pgbouncer"
  fi

  # Remove systemd overrides
  if [[ -d /etc/systemd/system/pgbouncer.service.d ]]; then
    rm -rf /etc/systemd/system/pgbouncer.service.d
    log_success "Removed PgBouncer systemd overrides"
  fi

  systemctl daemon-reload
}

# Remove data directories
remove_data() {
  log_info "Removing data directories..."

  # Remove PostgreSQL data
  if [[ -d /var/lib/postgresql ]]; then
    rm -rf /var/lib/postgresql
    log_success "Removed /var/lib/postgresql"
  fi

  # Remove PgBouncer logs
  if [[ -d /var/log/pgbouncer ]]; then
    rm -rf /var/log/pgbouncer
    log_success "Removed /var/log/pgbouncer"
  fi

  # Remove PgBouncer runtime directory
  if [[ -d /var/run/pgbouncer ]]; then
    rm -rf /var/run/pgbouncer
    log_success "Removed /var/run/pgbouncer"
  fi
}

# Remove backups
remove_backups() {
  log_info "Removing backup directories..."

  if [[ -d /var/backups/postgresql ]]; then
    rm -rf /var/backups/postgresql
    log_success "Removed /var/backups/postgresql"
  fi
}

# Remove SSL certificates
remove_ssl_certificates() {
  log_info "Checking for SSL certificates..."

  # Note: We don't remove Let's Encrypt certs as they might be used by other services
  # Only remove PostgreSQL-specific SSL directory if it exists
  if [[ -d /etc/postgresql/16/main/ssl ]]; then
    rm -rf /etc/postgresql/16/main/ssl
    log_success "Removed PostgreSQL SSL directory"
  fi

  log_warn "Let's Encrypt certificates in /etc/letsencrypt were NOT removed"
  log_warn "Remove them manually if needed: certbot delete --cert-name <domain>"
}

# Remove cron jobs
remove_cron_jobs() {
  log_info "Removing cron jobs..."

  # Remove backup cron job
  if crontab -l 2>/dev/null | grep -q "pg-backup-all"; then
    crontab -l | grep -v "pg-backup-all" | crontab -
    log_success "Removed PostgreSQL backup cron job"
  fi
}

# Remove management scripts
remove_management_scripts() {
  log_info "Removing management scripts..."

  local scripts=(
    "/usr/local/bin/pg-backup-all"
    "/usr/local/bin/pg-backup-control"
    "/usr/local/bin/pg-list-databases"
    "/usr/local/bin/pg-stats"
  )

  for script in "${scripts[@]}"; do
    if [[ -f "$script" ]]; then
      rm -f "$script"
      log_success "Removed $script"
    fi
  done
}

# Remove postgres user (optional)
remove_postgres_user() {
  log_warn "The 'postgres' system user will NOT be removed automatically"
  log_warn "To remove it manually, run: sudo deluser --remove-home postgres"
}

# Main execution
main() {
  show_banner
  ensure_root
  confirm_uninstall

  echo ""
  log_info "Starting uninstallation..."
  echo ""

  stop_services
  remove_cron_jobs
  remove_management_scripts
  remove_packages
  remove_configurations
  remove_data
  remove_backups
  remove_ssl_certificates
  remove_postgres_user

  echo ""
  log_success "Uninstallation completed!"
  echo ""

  echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║                                                                ║${NC}"
  echo -e "${GREEN}║          PostgreSQL has been completely removed!               ║${NC}"
  echo -e "${GREEN}║                                                                ║${NC}"
  echo -e "${GREEN}║  You can now run postgres-dns.sh for a fresh installation     ║${NC}"
  echo -e "${GREEN}║                                                                ║${NC}"
  echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

# Run main function
main "$@"
