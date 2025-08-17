#!/bin/bash

# This script automates the installation and activation of the systemd timers
# for the Mediarr backup and cleanup services.

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}--- Mediarr Backup System Activation Script ---${NC}"

# Check if running as root, since all commands require it
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}This script needs to be run with sudo.${NC}"
    echo "Please run it as: sudo $0"
    exit 1
fi

echo "Step 1: Copying systemd unit files to /etc/systemd/system/..."
cp /opt/mediarr/systemd/mediarr-backup.service /etc/systemd/system/
cp /opt/mediarr/systemd/mediarr-backup.timer /etc/systemd/system/
cp /opt/mediarr/systemd/mediarr-cleanup.service /etc/systemd/system/
cp /opt/mediarr/systemd/mediarr-cleanup.timer /etc/systemd/system/
echo "Done."
echo

echo "Step 2: Reloading the systemd daemon to recognize the new files..."
systemctl daemon-reload
echo "Done."
echo

echo "Step 3: Enabling and starting the backup and cleanup timers..."
systemctl enable --now mediarr-backup.timer
systemctl enable --now mediarr-cleanup.timer
echo "Done."
echo

echo -e "${GREEN}--- Verification ---${NC}"
echo "The timers are now active. You can check their status with:"
echo "systemctl list-timers | grep mediarr"
echo
systemctl list-timers | grep mediarr
echo
echo -e "${GREEN}Activation complete! The backup and cleanup jobs are now scheduled.${NC}"
