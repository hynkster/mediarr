#!/bin/bash

# Configuration variables
MEDIARR_ROOT="/opt/mediarr"
NAS_ROOT="/mnt/nas"
MEDIA_USER="$USER"
MEDIA_GROUP="$USER"
TIMEZONE="Europe/Vienna"
NAS_IP="192.168.2.13" # IMPORTANT: Change this to your NAS IP address

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
    error "Please run as root"
    exit 1
fi

# Create base directory structure
create_directory_structure() {
    log "Creating directory structure..."
    
    # Create main directories
    mkdir -p "${MEDIARR_ROOT}"/{config,cache,scripts,logs,data}/{jellyfin,plex,sonarr,radarr,qbittorrent,prowlarr,gluetun}
    mkdir -p "${NAS_ROOT}"/{movies,shows,dokus,downloads,flimmit}
    
    # Set permissions
    chown -R "$MEDIA_USER":"$MEDIA_GROUP" "$MEDIARR_ROOT"
    chmod -R 755 "$MEDIARR_ROOT"
    
    log "Directory structure created successfully"
}

# Create .env file
create_env_file() {
    log "Creating .env file..."
    if [ -f "${MEDIARR_ROOT}/.env" ]; then
        log "Existing .env file found. Skipping creation."
        return
    fi

    cp "${MEDIARR_ROOT}/.env.template" "${MEDIARR_ROOT}/.env"

    log "Please edit the .env file with your specific settings."
    log "You will need to provide your VPN credentials and API keys."
}

# Create NAS credentials file
create_nas_credentials() {
    log "Creating NAS credentials file..."
    
    # Prompt for credentials
    read -p "Enter NAS username: " nas_user
    read -s -p "Enter NAS password: " nas_pass
    echo
    
    # Create credentials file
    cat > /etc/nas-credentials <<EOF
username=$nas_user
password=$nas_pass
domain=WORKGROUP
EOF
    
    chmod 600 /etc/nas-credentials
    log "NAS credentials file created"
}

# Create docker-compose.yml
create_docker_compose() {
    log "Creating docker-compose.yml..."
    
    cat > "${MEDIARR_ROOT}/docker-compose.yml" <<EOF
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    network_mode: "host"
    volumes:
      - \">${MEDIARR_CONFIG}/jellyfin:/config
      - \">${MEDIARR_CACHE}:/cache
      - \">${NAS_MOVIES}:/media/movies
      - \">${NAS_SHOWS}:/media/shows
      - \">${NAS_DOKUS}:/media/dokus
      - \">${NAS_FLIMMIT}:/media/flimmit
    environment:
      - PUID=\">${PUID}
      - PGID=\">${PGID}
      - TZ=\">${TZ}
      - JELLYFIN_FFmpeg__EnableHardwareEncoding=true
      - JELLYFIN_FFmpeg__EnableVAAPI=true
      - JELLYFIN_FFmpeg__VAAPIDevice=/dev/dri/renderD128
      - JELLYFIN_FFmpeg__EncoderThreadCount=4
      - JELLYFIN_FFmpeg__HardwareDecodingCodecs=["h264"]
    devices:
      - /dev/dri/card1:/dev/dri/card1
      - /dev/dri/renderD128:/dev/dri/renderD128
    privileged: false  # Explicitly keep security
    group_add:
      - "989"
      - "985"
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G
    restart: unless-stopped
    healthcheck:
      test: [ "CMD", "curl", "-f", "http://localhost:8096/health" ]
      interval: 30s
      timeout: 10s
      retries: 3

  plex:
    image: lscr.io/linuxserver/plex:latest
    container_name: plex
    network_mode: "host"
    environment:
      - PUID=\">${PUID}
      - PGID=\">${PGID}
      - TZ=\">${TZ}
      - VERSION=docker
      - PLEX_CLAIM=\">${PLEX_CLAIM} # Claim token will only be used if uncommented in .env
    devices:
      - /dev/dri:/dev/dri
    privileged: false  # Explicitly keep security
    group_add:
      - "989" # render group
      - "985" # video group
    volumes:
      - \">${MEDIARR_CONFIG}/plex:/config
      - \">${MEDIARR_DATA}/plex/transcode:/transcode
      - \">${NAS_MOVIES}:/media/movies
      - \">${NAS_SHOWS}:/media/shows
      - \">${NAS_FLIMMIT}:/media/flimmit
      - /usr/share/libdrm:/home/runner/actions-runner/_work/plex-conan/plex-conan/.conan/data/libdrm/2.4.120-0/sixones/update-expat/build/73ee780ba6ea3ef381da6e7f229c475bfaf477ca/meson-install/share/libdrm:ro
    deploy:
      resources:
        limits:
          memory: 8G
        reservations:
          memory: 4G
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped

  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=\">${PUID}
      - PGID=\">${PGID}
      - TZ=\">${TZ}
    volumes:
      - \">${MEDIARR_CONFIG}/sonarr:/config
      - \">${NAS_SHOWS}:/tv/shows
      - \">${NAS_DOKUS}:/tv/dokus
      - \">${NAS_DOWNLOADS}:/downloads
    ports:
      - "8989:8989"
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped
    healthcheck:
      test: [ "CMD", "curl", "-f", "http://localhost:8989/health" ]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - mediarr_network

  radarr:
    image: linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=\">${PUID}
      - PGID=\">${PGID}
      - TZ=\">${TZ}
    volumes:
      - \">${MEDIARR_CONFIG}/radarr:/config
      - \">${NAS_MOVIES}:/movies
      - \">${NAS_DOWNLOADS}:/downloads
    ports:
      - "7878:7878"
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: [ "CMD", "curl", "-f", "http://localhost:7878/health" ]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - mediarr_network

  gluetun:
    image: qmcgaw/gluetun:v3
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    environment:
      - VPN_SERVICE_PROVIDER=protonvpn # mullvad, protonvpn
      - VPN_TYPE=wireguard
      - WIREGUARD_PRIVATE_KEY=\">${WIREGUARD_PRIVATE_KEY}
      - WIREGUARD_ADDRESSES=\">${WIREGUARD_ADDRESSES}
      - SERVER_COUNTRIES=Belgium
      - TZ=\">${TZ}
      - LOG_LEVEL=debug # debug, info, warning, error, fatal, panic

      - FIREWALL_VPN_INPUT_PORTS=6881,1337,6969,80,451 # qBittorrent incoming port
      - VPN_PORT_FORWARDING=on
      - VPN_PORT_FORWARDING_PROVIDER=protonvpn
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "8888:8888/tcp" # HTTP proxy port
      - "8388:8388/tcp" # SOCKS proxy port
      - \">${QB_PORT}:8080 # qBittorrent WebUI
      - \">${QB_INCOMING_PORT}:6881 # qBittorrent incoming
      - \">${QB_INCOMING_PORT}:6881/udp # qBittorrent incoming UDP
    volumes:
      - \">${MEDIARR_CONFIG}/gluetun:/gluetun
      - \">${MEDIARR_DATA}/gluetun:/tmp/gluetun
    restart: unless-stopped
    networks:
      - mediarr_network

  qbittorrent:
    image: linuxserver/qbittorrent:latest
    container_name: qbittorrent
    network_mode: "service:gluetun"
    environment:
      - PUID=\">${PUID}
      - PGID=\">${PGID}
      - TZ=\">${TZ}
      - WEBUI_PORT=8080
      - DOCKER_MODS=ghcr.io/vuetorrent/vuetorrent-lsio-mod:latest
    volumes:
      - \">${MEDIARR_CONFIG}/qbittorrent:/config
      - \">${NAS_DOWNLOADS}:/downloads
      - \">${MEDIARR_DATA}/gluetun:/gluetun-data
    #    ports:
    #      - \">${QB_PORT}:8080"
    #      - \">${QB_INCOMING_PORT}:6881"
    #      - \">${QB_INCOMING_PORT}:6881/udp"
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped

  prowlarr:
    image: linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=\">${PUID}
      - PGID=\">${PGID}
      - TZ=\">${TZ}
    volumes:
      - /opt/mediarr/config/prowlarr:/config
    ports:
      - \">${PROWLARR_PORT}:9696"
    restart: unless-stopped
    networks:
      - mediarr_network

  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    environment:
      - LOG_LEVEL=info
      - TZ=Europe/Vienna
      - CAPTCHA_SOLVER=none
    ports:
      - \">${FLARESOLVERR_PORT}:8191"
    restart: unless-stopped
    networks:
      - mediarr_network

  unpackerr:
    image: ghcr.io/unpackerr/unpackerr:latest
    container_name: unpackerr
    environment:
      - PUID=\">${PUID}
      - PGID=\">${PGID}
      - TZ=\">${TZ}
      - UN_SONARR_0_URL=http://sonarr:8989
      - UN_SONARR_0_API_KEY=\">${SONARR_API_KEY}
      - UN_RADARR_0_URL=http://radarr:7878
      - UN_RADARR_0_API_KEY=\">${RADARR_API_KEY}
      - UN_PATHS_0=/downloads
    volumes:
      - \">${NAS_DOWNLOADS}:/downloads
    restart: unless-stopped
    depends_on:
      - sonarr
      - radarr
    networks:
      - mediarr_network

networks:
  mediarr_network:
    driver: bridge
EOF
    
    chmod 644 "${MEDIARR_ROOT}/docker-compose.yml"
    log "docker-compose.yml created"
}

# Create systemd service for mounting NAS
create_mount_service() {
    log "Creating systemd mount service..."
    
    cat > /etc/systemd/system/mediarr-nas-mount.service <<EOF
[Unit]
Description=Mount Mediarr NAS shares
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/mount -a -t cifs
ExecStop=/bin/umount -a -t cifs
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF
    
    chmod 644 /etc/systemd/system/mediarr-nas-mount.service
    systemctl daemon-reload
    systemctl enable mediarr-nas-mount.service
    log "Mount service created and enabled"
}

# Configure fstab for NAS mounts
configure_fstab() {
    log "Configuring fstab..."
    
    # Backup existing fstab
    cp /etc/fstab /etc/fstab.backup
    
    # Add NAS mounts
    cat >> /etc/fstab <<EOF

# Mediarr NAS mounts
//${NAS_IP}/Media/Movies ${NAS_ROOT}/movies cifs credentials=/etc/nas-credentials,iocharset=utf8,vers=3.0,uid=1000,gid=1000,_netdev 0 0
//${NAS_IP}/Media/Shows ${NAS_ROOT}/shows cifs credentials=/etc/nas-credentials,iocharset=utf8,vers=3.0,uid=1000,gid=1000,_netdev 0 0
//${NAS_IP}/Media/Dokus ${NAS_ROOT}/dokus cifs credentials=/etc/nas-credentials,iocharset=utf8,vers=3.0,uid=1000,gid=1000,_netdev 0 0
//${NAS_IP}/Media/Downloads ${NAS_ROOT}/downloads cifs credentials=/etc/nas-credentials,iocharset=utf8,vers=3.0,uid=1000,gid=1000,_netdev 0 0
EOF
    
    log "fstab configured"
}

# Create systemd timer for port forwarding update
create_port_update_timer() {
    log "Creating systemd timer for port forwarding update..."

    # Create service file
    cat > /etc/systemd/system/update-port.service <<EOF
[Unit]
Description=Update qBittorrent port from Gluetun

[Service]
Type=oneshot
ExecStart=${MEDIARR_ROOT}/scripts/update-port.sh
EOF

    # Create timer file
    cat > /etc/systemd/system/update-port.timer <<EOF
[Unit]
Description=Run update-port.sh every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=update-port.service

[Install]
WantedBy=timers.target
EOF

    chmod 644 /etc/systemd/system/update-port.service
    chmod 644 /etc/systemd/system/update-port.timer

    systemctl daemon-reload
    systemctl enable --now update-port.timer
    log "Systemd timer for port forwarding update created and enabled."
}

# Install required packages
install_requirements() {
    log "Installing required packages..."
    
    if [ -x "$(command -v pacman)" ]; then
        pacman -S --noconfirm docker docker-compose cifs-utils curl htop iotop
    elif [ -x "$(command -v apt-get)" ]; then
        apt-get update
        apt-get install -y docker.io docker-compose cifs-utils curl htop iotop
    elif [ -x "$(command -v dnf)" ]; then
        dnf install -y docker docker-compose cifs-utils curl htop iotop
    else
        error "Could not find a supported package manager (pacman, apt-get, or dnf). Please install the required packages manually."
        return 1
    fi
    
    systemctl enable --now docker
    log "Required packages installed"
}

# Main setup function
main() {
    log "Starting Mediarr setup..."
    
    install_requirements
    create_directory_structure
    create_env_file
    create_nas_credentials
    create_docker_compose
    create_mount_service
    configure_fstab
    create_port_update_timer
    
    log "Setup completed successfully!"
    log "Next steps:"
    log "1. IMPORTANT: Edit the .env file at ${MEDIARR_ROOT}/.env to add your VPN credentials and API keys."
    log "2. Start the services with: sudo docker compose -f ${MEDIARR_ROOT}/docker-compose.yml up -d"
    log "3. Access your services and complete initial setup."
}

# Run setup
main
