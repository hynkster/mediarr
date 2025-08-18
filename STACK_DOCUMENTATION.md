# Mediarr Docker Stack Documentation

This document outlines the services and their interactions within the Mediarr Docker stack.

## Services

The stack is composed of the following services:

- **[Jellyfin](#jellyfin):** Media server for streaming content.
- **[Plex](#plex):** Alternative media server for streaming content.
- **[Sonarr](#sonarr):** Automates the downloading of TV shows.
- **[Radarr](#radarr):** Automates the downloading of movies.
- **[qBittorrent](#qbittorrent):** Torrent client for downloading content.
- **[Gluetun](#gluetun):** VPN client to ensure secure and private connections for qBittorrent.
- **[Prowlarr](#prowlarr):** Manages indexers for Sonarr and Radarr.
- **[Flaresolverr](#flaresolverr):** Bypasses Cloudflare protections for indexers.
- **[Unpackerr](#unpackerr):** Automatically extracts downloaded content.

## Service Details

### Jellyfin

- **Image:** `jellyfin/jellyfin:latest`
- **Purpose:** A free and open-source media server.
- **Network:** Host mode, directly using the host's network.
- **Volumes:**
    - `${MEDIARR_CONFIG}/jellyfin`:/config
    - `${MEDIARR_CACHE}`:/cache
    - `${NAS_MOVIES}`:/media/movies
    - `${NAS_SHOWS}`:/media/shows
    - `${NAS_DOKUS}`:/media/dokus
    - `${NAS_FLIMMIT}`:/media/flimmit
- **Hardware Acceleration:** Configured to use VAAPI for hardware-accelerated video encoding and decoding.

### Plex

- **Image:** `lscr.io/linuxserver/plex:latest`
- **Purpose:** A popular media server.
- **Network:** Host mode.
- **Volumes:**
    - `${MEDIARR_CONFIG}/plex`:/config
    - `${MEDIARR_DATA}/plex/transcode`:/transcode
    - `${NAS_MOVIES}`:/media/movies
    - `${NAS_SHOWS}`:/media/shows
    - `${NAS_FLIMMIT}`:/media/flimmit

### Sonarr

- **Image:** `linuxserver/sonarr:latest`
- **Purpose:** Manages and automatically downloads TV shows.
- **Network:** `mediarr_network`
- **Ports:** 8989
- **Volumes:**
    - `${MEDIARR_CONFIG}/sonarr`:/config
    - `${NAS_SHOWS}`:/tv/shows
    - `${NAS_DOKUS}`:/tv/dokus
    - `${NAS_DOWNLOADS}`:/downloads
- **Connections:** Connects to Radarr, qBittorrent, and Prowlarr.

### Radarr

- **Image:** `linuxserver/radarr:latest`
- **Purpose:** Manages and automatically downloads movies.
- **Network:** `mediarr_network`
- **Ports:** 7878
- **Volumes:**
    - `${MEDIARR_CONFIG}/radarr`:/config
    - `${NAS_MOVIES}`:/movies
    - `${NAS_DOWNLOADS}`:/downloads
- **Connections:** Connects to Sonarr, qBittorrent, and Prowlarr.

### qBittorrent

- **Image:** `linuxserver/qbittorrent:latest`
- **Purpose:** Downloads files via BitTorrent.
- **Network:** Uses the network of the `gluetun` service.
- **Volumes:**
    - `${MEDIARR_CONFIG}/qbittorrent`:/config
    - `${NAS_DOWNLOADS}`:/downloads
- **Connections:** All traffic is routed through Gluetun. Sonarr and Radarr send download requests to qBittorrent.

### Gluetun

- **Image:** `qmcgaw/gluetun:v3`
- **Purpose:** Provides a VPN connection for other services.
- **Network:** `mediarr_network`
- **Connections:** qBittorrent is configured to use Gluetun's network stack, ensuring all its traffic goes through the VPN.

### Prowlarr

- **Image:** `linuxserver/prowlarr:latest`
- **Purpose:** Manages torrent indexers and trackers for Sonarr and Radarr.
- **Network:** `mediarr_network`
- **Ports:** 9696
- **Volumes:**
    - `${MEDIARR_CONFIG}/prowlarr`:/config
- **Connections:** Provides indexer information to Sonarr and Radarr.

### Flaresolverr

- **Image:** `ghcr.io/flaresolverr/flaresolverr:latest`
- **Purpose:** A proxy to solve Cloudflare challenges for web scraping.
- **Network:** `mediarr_network`
- **Ports:** 8191
- **Connections:** Prowlarr uses Flaresolverr to access indexers protected by Cloudflare.

### Unpackerr

- **Image:** `ghcr.io/unpackerr/unpackerr:latest`
- **Purpose:** Automatically extracts compressed files downloaded by qBittorrent.
- **Network:** `mediarr_network`
- **Volumes:**
    - `${NAS_DOWNLOADS}`:/downloads
- **Connections:** Monitors the download directory for compressed files and extracts them. It is connected to Sonarr and Radarr to update their status.

## Networking

The `mediarr_network` is a bridge network that allows the containers to communicate with each other by their service name. Jellyfin and Plex are in `host` mode to allow for easier device discovery and hardware acceleration access on the local network.

## Data Flow

1.  **Request:** A user adds a movie or TV show to Radarr or Sonarr.
2.  **Search:** Radarr/Sonarr searches for the content on the indexers managed by Prowlarr.
3.  **Proxy:** If an indexer is protected by Cloudflare, Prowlarr uses Flaresolverr to bypass it.
4.  **Download:** Once found, the download is sent to qBittorrent.
5.  **VPN:** qBittorrent's traffic is routed through the Gluetun VPN.
6.  **Extraction:** After the download is complete, Unpackerr extracts the files.
7.  **Import:** Radarr/Sonarr imports the extracted files into the media library.
8.  **Streaming:** The media is now available for streaming via Jellyfin or Plex.

## Scripts

### `update.sh`

- **Purpose:** Automates the process of updating the Docker containers.
- **Functionality:**
    - Runs `backup.sh` to create a special `pre-update` backup of the configuration.
    - Uses Watchtower to check for and pull new Docker images.
    - Removes the Watchtower container after the update.
    - Prunes old Docker images to free up disk space.
- **Usage:** This script is run automatically every Sunday at 02:00 by the `mediarr-update.service` systemd unit, but can be run manually:
    ```bash
    sudo /opt/mediarr/scripts/update.sh
    ```

### `backup.sh`

- **Purpose:** Creates a backup of the service configurations.
- **Functionality:**
    - Stops the running Docker containers.
    - Creates a compressed archive of the `config` directory.
    - Stores the backup in a specified directory (default: `/mnt/nas/backups/mediarr`).
    - Restarts the Docker containers.
- **Usage:** This script is run automatically by the `mediarr-backup.service` systemd unit, but can be run manually:
    ```bash
    sudo /opt/mediarr/scripts/backup.sh
    ```

### `cleanup_backups.sh`

- **Purpose:** Cleans up old backups based on a retention policy.
- **Functionality:**
    - Deletes backups older than 14 days, but keeps the first backup of each month for the last 3 months.
- **Usage:** This script is run automatically by the `mediarr-cleanup.service` systemd unit.

### `activate_backup_system.sh`

- **Purpose:** Activates the automated backup and cleanup system.
- **Functionality:**
    - Copies the `systemd` service and timer files to `/etc/systemd/system`.
    - Enables and starts the `systemd` timers.
- **Usage:**
    ```bash
    sudo /opt/mediarr/scripts/activate_backup_system.sh
    ```

### `update-port.sh`

- **Purpose:** Automatically updates the qBittorrent listening port to match the one forwarded by Gluetun.
- **Functionality:**
    - Reads the forwarded port from the file generated by Gluetun.
    - Connects to the qBittorrent API to get the current listening port.
    - If the ports are different, it updates the port in qBittorrent.
    - Updates the `QB_INCOMING_PORT` variable in the `.env` file to match the new port.
- **Usage:**
    ```bash
    /opt/mediarr/scripts/update-port.sh
    ```

### `os-update.sh`

- **Purpose:** Automates the process of updating the host operating system.
- **Functionality:**
    - Detects the system's package manager (`apt` or `pacman`).
    - Runs the appropriate commands to update all system packages.
    - Reboots the system if a reboot is required after the update.
- **Usage:** This script is run automatically every day at 05:00 by the `mediarr-os-update.service` systemd unit, but can be run manually:
    ```bash
    sudo /opt/mediarr/scripts/os-update.sh
    ```
