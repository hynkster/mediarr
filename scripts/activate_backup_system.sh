#!/bin/bash

# This script automates the installation and activation of the systemd timers
# for the Mediarr backup and cleanup services.

# --- Configuration ---
MEDIARR_ROOT="/opt/mediarr"
SYSTEMD_SOURCE_DIR="$MEDIARR_ROOT/systemd"
SYSTEMD_TARGET_DIR="/etc/systemd/system"

# --- Color codes for output ---
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

echo "Step 1: Copying systemd unit files to $SYSTEMD_TARGET_DIR..."
# List of all services and timers to be managed
UNIT_FILES=(
    "mediarr-backup.service"
    "mediarr-backup.timer"
    "mediarr-cleanup.service"
    "mediarr-cleanup.timer"
    "mediarr-update.service"
    "mediarr-update.timer"
    "mediarr-os-update.service"
    "mediarr-os-update.timer"
)

# Loop through and copy each file
for unit_file in "${UNIT_FILES[@]}"; do
    echo "Copying $unit_file..."
    cp "$SYSTEMD_SOURCE_DIR/$unit_file" "$SYSTEMD_TARGET_DIR/"
done
echo "Done."
echo

echo "Step 2: Reloading the systemd daemon to recognize the new files..."
systemctl daemon-reload
echo "Done."
echo

echo "Step 3: Enabling and starting all timers..."
systemctl enable --now mediarr-backup.timer
systemctl enable --now mediarr-cleanup.timer
systemctl enable --now mediarr-update.timer
systemctl enable --now mediarr-os-update.timer
echo "Done."
echo

echo -e "${GREEN}--- Verification ---${NC}"
echo "The timers are now active. You can check their status with:"
echo "systemctl list-timers | grep mediarr"
echo
systemctl list-timers --all | grep mediarr
echo
echo -e "${GREEN}Activation complete! All jobs are now scheduled.${NC}"