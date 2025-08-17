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

This project now includes a script to automate the process of updating your Docker containers. The script uses [Watchtower](https://containrrr.dev/watchtower/) to update the containers and also creates a backup before starting the update process.

### How to Use the Update Script

The `update.sh` script is located in the `scripts` directory. It will:

1.  Run the `backup.sh` script to create a backup of your configuration.
2.  Start the Watchtower container to check for new images and update your containers.
3.  Remove the Watchtower container after the update is complete.
4.  Prune old Docker images to save disk space.

To run the update script, simply execute it as root:

```bash
sudo /opt/mediarr/scripts/update.sh
```

It's recommended to run this script periodically to keep your services up-to-date. You can set up a cron job to automate this process.

## Backup Strategy

Backing up your configuration is crucial to avoid losing your settings and metadata. This project includes a simple backup script to help you with this.

### How to Use the Backup Script

The `backup.sh` script is located in the `scripts` directory. It will:

1.  Stop the running Docker containers.
2.  Create a compressed backup of your `config` directory.
3.  Store the backup in `/mnt/nas/backups/mediarr` (you can change this in the script).
4.  Restart the Docker containers.

To run the backup script, simply execute it as root:

```bash
sudo /opt/mediarr/scripts/backup.sh
```

It's recommended to run this script periodically. You can set up a cron job to automate this process.

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
