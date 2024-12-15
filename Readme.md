# Mediarr - Complete Media Server Stack Setup Guide

## Overview

Mediarr is a comprehensive media server solution that combines multiple services to create a powerful and automated media management system. This guide will walk you through setting up a complete media server stack using Docker containers.

### Features

- Media streaming with hardware acceleration
- Automated TV show and movie downloads
- Automated media organization
- Comprehensive media management
- Integrated download client
- Indexer management

### Components

- **Jellyfin**: Media streaming server with hardware acceleration
- **Sonarr**: TV show management and automation
- **Radarr**: Movie management and automation
- **Prowlarr**: Indexer management
- **qBittorrent**: Download client with VueTorrent UI
- **FlareSolverr**: Bypass Cloudflare protection
- **Unpackerr**: Automated media extraction

## Prerequisites

- Linux server (tested on Manjaro)
- NAS or storage solution
- Docker and Docker Compose
- Basic command line knowledge
- Root or sudo access

## Repository Structure

```
mediarr/
├── README.md
├── scripts/
│   ├── setup.sh
│   └── update.sh
├── configs/
│   └── docker-compose.yml
└── docs/
    ├── INSTALLATION.md
    ├── CONFIGURATION.md
    └── TROUBLESHOOTING.md
```

## Quick Start

1. Clone the repository:
```bash
git clone https://github.com/yourusername/mediarr.git
cd mediarr
```

2. Make the setup script executable:
```bash
chmod +x scripts/setup.sh
```

3. Run the setup script:
```bash
sudo ./scripts/setup.sh
```

## Detailed Installation

### 1. System Preparation

Install required packages:
```bash
sudo pacman -S docker docker-compose cifs-utils curl htop iotop
```

Enable and start Docker:
```bash
sudo systemctl enable --now docker
```

### 2. Directory Structure

The setup script will create the following directory structure:
```
/opt/mediarr/
├── config/
│   ├── jellyfin/
│   ├── sonarr/
│   ├── radarr/
│   ├── qbittorrent/
│   └── prowlarr/
├── cache/
├── scripts/
└── logs/

/mnt/nas/
├── movies/
├── shows/
├── dokus/
└── downloads/
```

### 3. NAS Integration

The script will:
1. Create a secure credentials file
2. Configure automatic mounting
3. Set up proper permissions

### 4. Service Configuration

Each service is configured with:
- Proper permissions (PUID/PGID)
- Volume mappings
- Network settings
- Security options
- Health checks

#### Jellyfin Configuration
- Hardware acceleration enabled
- VAAPI configured for AMD GPUs
- Resource limits set
- Host network mode for best performance

#### Sonarr/Radarr Configuration
- Mapped to appropriate media directories
- Download client integration
- API access for automation

#### qBittorrent Configuration
- VueTorrent UI enabled
- Proper port mappings
- Download directory integration

## Post-Installation Setup

### 1. Initial Access

Access your services at:
- Jellyfin: `http://localhost:8096`
- Sonarr: `http://localhost:8989`
- Radarr: `http://localhost:7878`
- qBittorrent: `http://localhost:8080`
- Prowlarr: `http://localhost:9696`
- FlareSolverr
