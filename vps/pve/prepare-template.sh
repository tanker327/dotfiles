#!/bin/bash

# Exit on any error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Starting Template Preparation..."
echo "WARNING: This will clean sensitive data and prepare VM for templating"

# Check if running in a pipe (non-interactive)
if [ -t 0 ]; then
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
else
    echo "Running in non-interactive mode (piped from curl)"
    echo "Proceeding automatically in 5 seconds... Press Ctrl+C to cancel"
    sleep 5
fi

# 1. Update the System
echo "--- Updating System Packages ---"
apt update && apt upgrade -y

# 2. Install Essential Tools
echo "--- Installing Cloud-Init and QEMU Guest Agent ---"
apt install -y cloud-init qemu-guest-agent
systemctl enable qemu-guest-agent

# 3. Clean Package Cache
echo "--- Cleaning APT Cache ---"
apt clean
apt autoremove -y

# 4. Clear Log Files
echo "--- Clearing Log Files ---"
# Truncate all log files in /var/log to 0 size
find /var/log -type f -exec truncate -s 0 {} \;
# Remove archived logs
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete

# 5. Reset Machine ID (Critical)
echo "--- Resetting Machine ID ---"
truncate -s 0 /etc/machine-id
# Force the symlink for dbus machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# 6. Configure Cloud-Init Datasource (Speed Up Boot)
echo "--- Configuring Cloud-Init Datasource ---"
# This prevents the VM from waiting for AWS/Azure/GCP metadata servers
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-pve.cfg << EOF
datasource_list: [ NoCloud, ConfigDrive, None ]
EOF

# 7. Remove Persistent Network Rules
echo "--- Removing Persistent Network Rules ---"
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f /etc/udev/rules.d/75-persistent-net-generator.rules

# 8. Clean Network Config (Netplan)
echo "--- Cleaning Network Config ---"
# Removes installer network config so Cloud-Init takes over
rm -f /etc/netplan/*

# 9. Remove SSH Host Keys (Critical)
echo "--- Removing SSH Host Keys ---"
# WARNING: If you disconnect SSH after this step, you cannot log back in until a reboot/regeneration!
rm -f /etc/ssh/ssh_host_*

# 10. Reset Cloud-Init
echo "--- Resetting Cloud-Init ---"
cloud-init clean

# 11. Clean DHCP Leases
echo "--- Removing DHCP Leases ---"
rm -f /var/lib/dhcp/*

# 12. Clear Temporary Directories
echo "--- Cleaning Temporary Directories ---"
rm -rf /tmp/*
rm -rf /var/tmp/*

# 13. Clear Bash History
echo "--- Clearing History ---"
unset HISTFILE
rm -f /root/.bash_history
rm -f /home/*/.bash_history

echo "======================================================="
echo "Template preparation complete!"
echo "The Machine ID and SSH keys have been wiped."
echo "Cloud-init has been reset and configured for Proxmox."
echo "======================================================="

# Optional shutdown
if [ -t 0 ]; then
    read -p "Shutdown now to convert to template? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Shutting down in 5 seconds..."
        sleep 5
        shutdown -h now
    else
        echo "Please manually shut down the VM when ready to convert to template."
    fi
else
    echo "Running in non-interactive mode - NOT shutting down automatically."
    echo "Please manually shut down the VM when ready to convert to template."
fi