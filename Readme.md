# Mediarr - My Home Media Server Setup

Hey there! 👋 This is my personal setup for running a media server at home. I've put together this collection of scripts and guides to help friends set up their own media servers using the Arr stack (Sonarr, Radarr, etc.) and Jellyfin or Plex.

## What's This All About?

This is basically everything you need to run your own Netflix-like setup at home. It'll help you:
- Stream your media anywhere in your house
- Automatically organize your movies and TV shows
- Keep track of your shows and download new episodes
- Handle media downloads cleanly and automatically

## What's Included?
- Setup scripts to get everything running
- A guide that explains how everything works
- Configuration files you can use as templates
- Tips and tricks I learned while setting this up

## Requirements
- A Linux machine or server (I use Manjaro)
- Some basic command line knowledge
- A NAS or hard drives for storage
- Basic networking knowledge (helpful but not required)

## Warning ⚠️
This is a personal project - not professional software! It works for me, but you might need to tweak things for your setup. Feel free to ask questions or suggest improvements!

## Monitoring and Notifications

This project now includes [Healthchecks](https://healthchecks.io/), a service for monitoring your services and sending notifications. A self-hosted instance of Healthchecks is included in the `docker-compose.yml` file.

### Setting up Healthchecks

1.  **Configure Email:** Open your `.env` file and fill in the `HC_*` variables with your email server details. This is necessary for Healthchecks to be able to send you notifications.
2.  **Start the Stack:** Run `sudo docker compose up -d` to start all the services, including Healthchecks.
3.  **Access Healthchecks:** Open your browser and go to `http://<your-server-ip>:8000`. You will be able to create a user account and set up your checks.
4.  **Create Checks:** For each service you want to monitor, create a new check in the Healthchecks UI. You will get a unique URL for each check.
5.  **Integrate with Services:** You can use the check URLs to monitor your services. For services that have a `healthcheck` in the `docker-compose.yml` file, you can create a simple script to check the container's health and ping the Healthchecks URL. For scripts, you can add a `curl` command to the end of the script to ping the URL when the script completes successfully.

## Automated Updates

This project includes a script to automate the process of updating your Docker containers. The script is run automatically every Sunday at 02:00 by a `systemd` timer.

### How it Works

The `update.sh` script will:

1.  Run the `backup.sh` script to create a special `pre-update` backup of your configuration.
2.  Start a Watchtower container to check for new images and update your running services.
3.  Remove the Watchtower container after the update is complete.
4.  Prune old Docker images to save disk space.

### Activation
The automated update system is activated along with the backup system. Simply run the activation script as root:
```bash
sudo /opt/mediarr/scripts/activate_backup_system.sh
```
This will enable the weekly update timer along with the backup and cleanup timers.

### Manual Update
If you need to run an update manually, you can execute the script directly:
```bash
sudo /opt/mediarr/scripts/update.sh
```

## Automated Backup & Recovery

A fully automated backup and cleanup system is now in place using `systemd` timers.

### Features
- **Daily Backups:** A backup of your entire `/opt/mediarr/config` directory is created every day at 03:00.
- **Automated Cleanup:** Old backups are automatically deleted at 04:00 based on a retention policy to save disk space.
- **Smart Retention Policy:**
    - Keeps all daily backups for the last 14 days.
    - Keeps the first backup of the month for the last 3 months.
    - All other older backups are automatically removed.

### Activation
To activate the automated backup system, simply run the activation script as root:
```bash
sudo /opt/mediarr/scripts/activate_backup_system.sh
```
This script will copy the `systemd` service and timer files to the correct location and enable them. No manual cron job setup is required.

### Manual Backup
If you need to create a backup outside of the scheduled time, you can run the backup script manually:
```bash
sudo /opt/mediarr/scripts/backup.sh
```

### How to Restore from a Backup

To restore from a backup, you will need to:

1.  Stop your Docker containers: `sudo docker compose stop`
2.  Extract the contents of your backup file to the `config` directory, overwriting the existing files. For example:
    ```bash
    sudo tar -xzf /mnt/nas/backups/mediarr/mediarr_backup_YYYYMMDD_HHMMSS.tar.gz -C /opt/mediarr
    ```
3.  Restart your Docker containers: `sudo docker compose start`

## Port Forwarding for qBittorrent

To ensure optimal performance with qBittorrent, this setup includes a script to automatically update the listening port from the VPN service.

### How to Use the Port Update Script

The `update-port.sh` script is located in the `scripts` directory. It will:

1.  Read the forwarded port from Gluetun.
2.  Connect to the qBittorrent API.
3.  Update the listening port in qBittorrent to match the one from Gluetun.
4.  Update the `QB_INCOMING_PORT` variable in your `.env` file.

To run the port update script, simply execute it:

```bash
/opt/mediarr/scripts/update-port.sh
```

It's recommended to run this script periodically to ensure the port is always up-to-date. You can set up a cron job to automate this process.

## Questions?
If you run into issues or need help, just open an issue here on GitHub. I'll help when I can!

Happy streaming! 🍿
