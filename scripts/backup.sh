#!/bin/bash

# Configuration
BACKUP_DIR="/mnt/nas/backups/mediarr"
MEDIARR_ROOT="/opt/mediarr"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/mediarr_backup_${TIMESTAMP}.tar.gz"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date "+%Y-%m-%d %H:%M:%S")]${NC} $1"
}

error() {
    echo -e "${RED}[$(date "+%Y-%m-%d %H:%M:%S")] ERROR:${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root"
    exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Main backup function
main() {
    log "Starting Mediarr backup..."

    cd "$MEDIARR_ROOT" || exit

    log "Stopping services..."
    if ! docker compose stop; then
        error "Failed to stop services. Aborting backup."
        exit 1
    fi

    log "Creating backup of config directory..."
    if ! tar -czf "$BACKUP_FILE" -C "$MEDIARR_ROOT" config; then
        error "Failed to create backup file. Aborting backup."
        docker compose start
        exit 1
    fi

    log "Starting services..."
    if ! docker compose start; then
        error "Failed to start services."
        exit 1
    fi

    log "Backup completed successfully!"
    log "Backup file: $BACKUP_FILE"
}

# Run backup
main
