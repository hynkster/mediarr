#!/bin/bash

# Configuration
MEDIARR_ROOT="/opt/mediarr"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date \'+%Y-%m-%d %H:%M:%S\')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date \'+%Y-%m-%d %H:%M:%S\')] ERROR:${NC} $1"
}

# Check if running as root
# if [ "$EUID" -ne 0 ]; then
#     error "Please run as root"
#     exit 1
# fi

# Main update function
main() {
    log "Starting Mediarr update..."

    cd "$MEDIARR_ROOT" || exit

    log "Running backup before update..."
    if ! "${MEDIARR_ROOT}/scripts/backup.sh" "pre-update"; then
        error "Backup failed. Aborting update."
        exit 1
    fi

    log "Starting Watchtower to update containers..."
    if ! docker compose up -d watchtower; then
        error "Failed to start Watchtower."
        exit 1
    fi

    log "Waiting for Watchtower to finish..."
    if ! docker wait watchtower; then
        error "Failed to wait for Watchtower."
        exit 1
    fi

    log "Removing Watchtower container..."
    if ! docker compose rm -f -s -v watchtower; then
        error "Failed to remove Watchtower container."
        exit 1
    fi

    log "Pruning old Docker images..."
    if ! docker image prune -f; then
        error "Failed to prune Docker images."
        exit 1
    fi

    log "Update completed successfully!"
}

# Run update
main
