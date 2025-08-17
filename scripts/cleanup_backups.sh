#!/bin/bash

# Configuration
BACKUP_DIR="/mnt/nas/backups/mediarr"
NOW=$(date +%s)
FOURTEEN_DAYS_AGO=$(date -d "14 days ago" +%s)
THREE_MONTHS_AGO=$(date -d "3 months ago" +%Y-%m-01)

# Logging function
log() {
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $1"
}

log "Starting backup cleanup process..."

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    log "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

# Find and process backup files
find "$BACKUP_DIR" -name "mediarr_backup_*.tar.gz" | while read -r backup_file; do
    # Extract timestamp from filename
    timestamp_str=$(echo "$backup_file" | sed -n 's/.*mediarr_backup_\([0-9]\{8\}_[0-9]\{6\}\)\.tar\.gz/\1/p')
    if [ -z "$timestamp_str" ]; then
        log "Could not parse timestamp from: $backup_file"
        continue
    fi

    # Convert timestamp to seconds since epoch
    backup_date=$(date -d "${timestamp_str:0:8} ${timestamp_str:9:2}:${timestamp_str:11:2}:${timestamp_str:13:2}" +%s)
    backup_ymd=$(date -d "@$backup_date" +%Y-%m-%d)
    backup_day=$(date -d "@$backup_date" +%d)
    backup_ym=$(date -d "@$backup_date" +%Y-%m)

    # --- Retention Logic ---

    # 1. Keep all backups within the last 14 days
    if [ "$backup_date" -ge "$FOURTEEN_DAYS_AGO" ]; then
        log "KEEP (daily): $backup_file (less than 14 days old)"
        continue
    fi

    # 2. Keep the first backup of the month for the last 3 months
    # Check if the backup is from after the three-month cutoff
    if [[ "$backup_ymd" > "$THREE_MONTHS_AGO" ]]; then
        # Find the first backup of that month
        first_backup_of_month=$(find "$BACKUP_DIR" -name "mediarr_backup_${backup_ym}*.tar.gz" | sort | head -n 1)
        if [ "$backup_file" == "$first_backup_of_month" ]; then
            log "KEEP (monthly): $backup_file (first backup of the month)"
            continue
        fi
    fi

    # 3. If none of the above conditions are met, delete the backup
    log "DELETE: $backup_file"
    rm "$backup_file"
done

log "Backup cleanup process finished."
