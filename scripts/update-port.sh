#!/bin/bash

source /opt/mediarr/.env

# Configuration
LOG_FILE="/opt/mediarr/logs/port_forward.log"
#!/bin/bash

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to authenticate with qBittorrent
get_auth_cookie() {
    local cookie
    cookie=$(curl -s -i --header "Referer: http://${QB_HOST}:${QB_PORT}" \
        -d "username=${QB_USERNAME}&password=${QB_PASSWORD}" \
        "http://${QB_HOST}:${QB_PORT}/api/v2/auth/login" | grep -i "set-cookie" | cut -d' ' -f2)
    
    if [ -z "$cookie" ]; then
        log "Failed to authenticate with qBittorrent"
        return 1
    fi
    
    echo "$cookie"
}

# Function to get current qBittorrent port
get_current_port() {
    local cookie="$1"
    local port
    
    port=$(curl -s --cookie "$cookie" --header "Referer: http://${QB_HOST}:${QB_PORT}" \
        "http://${QB_HOST}:${QB_PORT}/api/v2/app/preferences" | \
        grep -o '"listen_port":[0-9]*' | cut -d':' -f2)
    
    echo "$port"
}

# Function to update qBittorrent port
update_port() {
    local cookie="$1"
    local new_port="$2"
    
    curl -s --cookie "$cookie" --header "Referer: http://${QB_HOST}:${QB_PORT}" \
        -d "json={\"listen_port\": $new_port}" \
        "http://${QB_HOST}:${QB_PORT}/api/v2/app/setPreferences"
    
    return $?
}

# Main script
main() {
    # Check if gluetun port file exists
    if [ ! -f "$GLUETUN_PORT_FILE" ]; then
        log "Gluetun port file not found: $GLUETUN_PORT_FILE"
        exit 1
    fi
    
    # Read new port from gluetun
    new_port=$(cat "$GLUETUN_PORT_FILE")
    if [ -z "$new_port" ] || ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
        log "Invalid port number from gluetun: $new_port"
        exit 1
    fi
    
    # Get authentication cookie
    cookie=$(get_auth_cookie)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # Get current port
    current_port=$(get_current_port "$cookie")
    if [ -z "$current_port" ]; then
        log "Failed to get current port from qBittorrent"
        exit 1
    fi
    
    # Update port if different
    if [ "$current_port" != "$new_port" ]; then
        log "Updating port from $current_port to $new_port"
        if update_port "$cookie" "$new_port"; then
            log "Successfully updated port to $new_port"
        else
            log "Failed to update port"
            exit 1
        fi
    else
        log "Port unchanged: $current_port"
    fi
}

# Run main function
main