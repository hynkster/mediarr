#!/bin/bash

# Configuration variables
MEDIARR_ROOT="/opt/mediarr"
NAS_ROOT="/mnt/nas"
MEDIA_USER="$USER"
MEDIA_GROUP="$USER"
TIMEZONE="Europe/Vienna"

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
}

# Create base directory structure
create_directory_structure() {
    log "Creating directory structure..."
    
    # Create main directories
    mkdir -p "${MEDIARR_ROOT}"/{config,cache,scripts,logs}/{jellyfin,sonarr,radarr,qbittorrent,prowlarr}
    mkdir -p "${NAS_ROOT}"/{movies,shows,dokus,downloads}
    
    # Set permissions
    chown -R "$MEDIA_USER":"$MEDIA_GROUP" "$MEDIARR_ROOT"
    chmod -R 755 "$MEDIARR_ROOT"
    
    log "Directory structure created successfully"
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
      - ${MEDIARR_ROOT}/config/jellyfin:/config
      - ${MEDIARR_ROOT}/cache:/cache
      - ${NAS_ROOT}/movies:/media/movies:ro
      - ${NAS_ROOT}/shows:/media/shows:ro
      - ${NAS_ROOT}/dokus:/media/dokus:ro
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TIMEZONE}
      - JELLYFIN_FFmpeg__EnableHardwareEncoding=true
      - JELLYFIN_FFmpeg__EnableVAAPI=true
      - JELLYFIN_FFmpeg__VAAPIDevice=/dev/dri/renderD128
      - JELLYFIN_FFmpeg__EncoderThreadCount=4
      - JELLYFIN_FFmpeg__HardwareDecodingCodecs=["h264"]
    devices:
      - /dev/dri/card1:/dev/dri/card1
      - /dev/dri/renderD128:/dev/dri/renderD128
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

  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TIMEZONE}
    volumes:
      - ${MEDIARR_ROOT}/config/sonarr:/config
      - ${NAS_ROOT}/shows:/tv/shows
      - ${NAS_ROOT}/dokus:/tv/dokus
      - ${NAS_ROOT}/downloads:/downloads
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

  radarr:
    image: linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TIMEZONE}
    volumes:
      - ${MEDIARR_ROOT}/config/radarr:/config
      - ${NAS_ROOT}/movies:/movies
      - ${NAS_ROOT}/downloads:/downloads
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

  qbittorrent:
    image: linuxserver/qbittorrent:latest
    container_name: qbittorrent
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TIMEZONE}
      - WEBUI_PORT=8080
      - DOCKER_MODS=ghcr.io/vuetorrent/vuetorrent-lsio-mod:latest
    volumes:
      - ${MEDIARR_ROOT}/config/qbittorrent:/config
      - ${NAS_ROOT}/downloads:/downloads
    ports:
      - "8080:8080"
      - "6881:6881"
      - "6881:6881/udp"
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped

  prowlarr:
    image: linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TIMEZONE}
    volumes:
      - ${MEDIARR_ROOT}/config/prowlarr:/config
    ports:
      - "9696:9696"
    restart: unless-stopped

  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    environment:
      - LOG_LEVEL=info
      - TZ=${TIMEZONE}
      - CAPTCHA_SOLVER=none
    ports:
      - "8191:8191"
    restart: unless-stopped

  unpackerr:
    image: ghcr.io/unpackerr/unpackerr:latest
    container_name: unpackerr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TIMEZONE}
      - UN_SONARR_0_URL=http://sonarr:8989
      - UN_RADARR_0_URL=http://radarr:7878
      - UN_PATHS_0=/downloads
    volumes:
      - ${NAS_ROOT}/downloads:/downloads
    restart: unless-stopped
    depends_on:
      - sonarr
      - radarr
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
//192.168.2.13/Media/Movies ${NAS_ROOT}/movies cifs credentials=/etc/nas-credentials,iocharset=utf8,vers=3.0,uid=1000,gid=1000,_netdev 0 0
//192.168.2.13/Media/Shows ${NAS_ROOT}/shows cifs credentials=/etc/nas-credentials,iocharset=utf8,vers=3.0,uid=1000,gid=1000,_netdev 0 0
//192.168.2.13/Media/Dokus ${NAS_ROOT}/dokus cifs credentials=/etc/nas-credentials,iocharset=utf8,vers=3.0,uid=1000,gid=1000,_netdev 0 0
//192.168.2.13/Media/Downloads ${NAS_ROOT}/downloads cifs credentials=/etc/nas-credentials,iocharset=utf8,vers=3.0,uid=1000,gid=1000,_netdev 0 0
EOF
    
    log "fstab configured"
}

# Install required packages
install_requirements() {
    log "Installing required packages..."
    pacman -S --noconfirm \
        docker \
        docker-compose \
        cifs-utils \
        curl \
        htop \
        iotop
    
    systemctl enable --now docker
    log "Required packages installed"
}

# Main setup function
main() {
    log "Starting Mediarr setup..."
    
    install_requirements
    create_directory_structure
    create_nas_credentials
    create_docker_compose
    create_mount_service
    configure_fstab
    
    log "Setup completed successfully!"
    log "Next steps:"
    log "1. Start the services with: sudo docker-compose -f ${MEDIARR_ROOT}/docker-compose.yml up -d"
    log "2. Access your services and complete initial setup:"
    log "   - Jellyfin: http://localhost:8096"
    log "   - Sonarr: http://localhost:8989"
    log "   - Radarr: http://localhost:7878"
    log "   - qBittorrent: http://localhost:8080"
    log "   - Prowlarr: http://localhost:9696"
    log "   - FlareSolverr: http://localhost:8191"
    log ""
    log "3. After initial setup, configure Unpackerr:"
    log "   a. Get your API keys from:"
    log "      - Sonarr: Settings -> General -> API Key"
    log "      - Radarr: Settings -> General -> API Key"
    log "   b. Update the docker-compose.yml file with your API keys:"
    log "      - UN_SONARR_0_API_KEY=your_sonarr_api_key"
    log "      - UN_RADARR_0_API_KEY=your_radarr_api_key"
    log "   c. Restart the unpackerr service:"
    log "      sudo docker-compose restart unpackerr"
}

# Run setup
main
