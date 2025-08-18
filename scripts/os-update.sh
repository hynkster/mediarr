#!/bin/bash

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
    exit 1
fi

# Update OS function
update_os() {
    log "Starting OS update..."
    if [ -x "$(command -v apt-get)" ]; then
        # Debian/Ubuntu based systems
        log "Detected apt-get package manager."
        if ! apt-get update; then
            error "Failed to update package lists."
            return 1
        fi
        if ! apt-get dist-upgrade -y; then
            error "Failed to upgrade OS."
            return 1
        fi
        log "Cleaning up old packages..."
        if ! apt-get autoremove -y; then
            error "Failed to autoremove packages."
        fi
        if ! apt-get clean; then
            error "Failed to clean package cache."
        fi
    elif [ -x "$(command -v pacman)" ]; then
        # Arch/Manjaro based systems
        log "Detected pacman package manager."
        if ! pacman -Syu --noconfirm; then
            error "Failed to update OS."
            return 1
        fi
    else
        error "Unsupported package manager. Skipping OS update."
        return 1
    fi

    log "OS update completed successfully."
    if [ -f /var/run/reboot-required ]; then
        log "Reboot required. Rebooting now..."
        reboot
    fi
}

# Run the update
update_os
