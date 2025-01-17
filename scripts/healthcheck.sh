#!/usr/bin/env bash

# Load environment variables
source "/opt/mediarr/.env"

# Configuration
LOG_FILE="/tmp/portwatch-health.log"
MAX_FAILURES=3
FAILURE_COUNT_FILE="/tmp/port_failures"
LAST_SUCCESS_FILE="/tmp/last_port_success"

# Initialize failure count if it doesn't exist
if [ ! -f "$FAILURE_COUNT_FILE" ]; then
    echo "0" > "$FAILURE_COUNT_FILE"
fi

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if qBittorrent is accessible
check_qbittorrent() {
    if ! curl -sf "http://localhost:8080/api/v2/app/version" > /dev/null; then
        return 1
    fi
    return 0
}

# Check if VPN is connected
check_vpn() {
    if ! curl -sf --interface tun0 "https://api.protonvpn.ch/vpn/location" > /dev/null; then
        return 1
    fi
    return 0
}

# Check port forwarding status
check_port_forwarding() {
    # Get current qBittorrent port
    local qb_port=$(curl -sf "http://localhost:8080/api/v2/app/preferences" | jq -r '.listen_port')
    
    # Check if port is actually accessible
    if ! nc -zv localhost "$qb_port" > /dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Main health check function
main() {
    local failures=$(cat "$FAILURE_COUNT_FILE")
    local status=0

    # Check VPN connection
    if ! check_vpn; then
        log "ERROR: VPN connection check failed"
        status=1
    fi

    # Check qBittorrent accessibility
    if ! check_qbittorrent; then
        log "ERROR: qBittorrent service check failed"
        status=1
    fi

    # Check port forwarding
    if ! check_port_forwarding; then
        log "ERROR: Port forwarding check failed"
        status=1
    fi

    if [ $status -eq 0 ]; then
        log "Health check passed"
        echo "0" > "$FAILURE_COUNT_FILE"
        date +%s > "$LAST_SUCCESS_FILE"
        exit 0
    else
        failures=$((failures + 1))
        echo "$failures" > "$FAILURE_COUNT_FILE"
        
        if [ "$failures" -ge "$MAX_FAILURES" ]; then
            log "CRITICAL: $MAX_FAILURES consecutive health check failures"
            # Could add system notification here if desired
            # notify-send "Port Forwarding Alert" "Critical: Multiple health check failures detected"
        fi
        
        exit 1
    fi
}

# Run main function
main