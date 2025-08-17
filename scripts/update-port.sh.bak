#!/bin/bash

# Load environment variables
ENV_FILE="/opt/mediarr/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Source the environment file
set -a
source "$ENV_FILE"
set +a

# Configuration from environment variables
LOG_FILE="${MEDIARR_ROOT}/logs/port_forward.log"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function with improved formatting
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to authenticate with qBittorrent
get_auth_cookie() {
    local cookie
    cookie=$(curl -s -i --header "Referer: http://${QB_HOST}:${QB_PORT}" \
        -d "username=${QB_USERNAME}&password=${QB_PASSWORD}" \
        "http://${QB_HOST}:${QB_PORT}/api/v2/auth/login" | grep -i "set-cookie" | cut -d' ' -f2)
    
    if [ -z "$cookie" ]; then
        log "ERROR" "Failed to authenticate with qBittorrent"
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

# Verify required environment variables
check_required_vars() {
    local missing_vars=()
    
    # Check required variables from .env
    if [ -z "${QB_USERNAME}" ]; then missing_vars+=("QB_USERNAME"); fi
    if [ -z "${QB_PASSWORD}" ]; then missing_vars+=("QB_PASSWORD"); fi
    if [ -z "${QB_HOST}" ]; then missing_vars+=("QB_HOST"); fi
    if [ -z "${QB_PORT}" ]; then missing_vars+=("QB_PORT"); fi
    if [ -z "${GLUETUN_PORT_FILE}" ]; then missing_vars+=("GLUETUN_PORT_FILE"); fi
    if [ -z "${MEDIARR_ROOT}" ]; then missing_vars+=("MEDIARR_ROOT"); fi
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log "ERROR" "Missing required environment variables: ${missing_vars[*]}"
        exit 1
    fi
}

# Main script
main() {
    log "INFO" "Starting port forwarding update check"
    
    # Check required environment variables
    check_required_vars
    
    # Check if gluetun port file exists
    if [ ! -f "$GLUETUN_PORT_FILE" ]; then
        log "ERROR" "Gluetun port file not found: $GLUETUN_PORT_FILE"
        exit 1
    fi
    
    # Read new port from gluetun
    new_port=$(cat "$GLUETUN_PORT_FILE")
    if [ -z "$new_port" ] || ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
        log "ERROR" "Invalid port number from gluetun: $new_port"
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
        log "ERROR" "Failed to get current port from qBittorrent"
        exit 1
    fi
    
    # Update port if different
    if [ "$current_port" != "$new_port" ]; then
        log "INFO" "Updating port from $current_port to $new_port"
        if update_port "$cookie" "$new_port"; then
            log "INFO" "Successfully updated port to $new_port"
            # Update QB_INCOMING_PORT in .env file
            sed -i "s/^QB_INCOMING_PORT=.*/QB_INCOMING_PORT=$new_port/g" "$ENV_FILE"
            log "INFO" "Updated QB_INCOMING_PORT in .env file"
        else
            log "ERROR" "Failed to update port"
            exit 1
        fi
    else
        log "INFO" "Port unchanged: $current_port"
    fi
}

# Run main function
main