# Proxmox VE (PVE) Scripts

This directory contains scripts for managing Proxmox VE virtual machines and templates.

## Files

### prepare-template.sh

A comprehensive script to prepare a VM before converting it to a template in Proxmox VE.

#### Purpose

When creating a VM template in Proxmox, you need to remove unique identifiers and clean sensitive data to ensure cloned VMs generate their own unique values. This script automates all the necessary preparation steps.

#### What It Does

1. **System Updates**: Updates and upgrades all packages
2. **Essential Tools**: Installs cloud-init and QEMU guest agent
3. **Package Cleanup**: Removes package cache and unused packages
4. **Log Cleanup**: Truncates and removes all log files
5. **Machine ID Reset**: Clears machine-id (critical for unique VM identification)
6. **Cloud-init Configuration**: Configures NoCloud-only datasource with timeouts (fixes 1-2 min boot delay)
7. **Network Rules**: Removes persistent network interface rules
8. **Netplan Cleanup**: Removes all netplan configs to prevent cloud-init conflicts
9. **SSH Keys**: Removes all SSH host keys (regenerated on first boot)
10. **Cloud-init Reset**: Cleans cloud-init state for fresh initialization
11. **DHCP Leases**: Removes DHCP lease files
12. **Temporary Files**: Cleans /tmp and /var/tmp directories
13. **Shell History**: Clears bash history for all users

#### Usage

**Option 1: Remote execution via curl (recommended)**

```bash
# One-line command to download and execute
curl -fsSL https://raw.githubusercontent.com/tanker327/dotfiles/master/vps/pve/prepare-template.sh | sudo bash
```

**Option 2: Download and run locally**

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/tanker327/dotfiles/master/vps/pve/prepare-template.sh -o prepare-template.sh

# Make it executable
chmod +x prepare-template.sh

# Run it
sudo ./prepare-template.sh
```

**Option 3: Clone the repository**

```bash
# Clone the dotfiles repo
git clone https://github.com/tanker327/dotfiles.git
cd dotfiles/vps/pve

# Run the script
sudo bash prepare-template.sh
```

The script will:
- Ask for confirmation before proceeding
- Execute all cleanup steps with progress messages
- Offer to shut down the VM automatically when complete

#### Key Features

**1. Slow Boot Fix (Cloud-Init Datasource)**

By default, cloud-init checks for AWS, Azure, and Google Cloud metadata servers, causing 1-2 minute boot delays. This script configures cloud-init to only use the NoCloud datasource (Proxmox's method) with short timeouts, eliminating the delay.

**2. Network Conflict Fix (Netplan Removal)**

Ubuntu's installer creates netplan configuration files (e.g., `/etc/netplan/00-installer-config.yaml`) that can conflict with cloud-init's network settings. The script removes all netplan configs, giving cloud-init a clean slate to configure networking from Proxmox's cloud-init settings (static IP or DHCP).

#### Important Notes

- **Run as root**: The script requires root privileges
- **SSH Warning**: After removing SSH host keys, you cannot log back in until the VM is rebooted
- **One-time use**: Run this script only when ready to convert the VM to a template
- **Backup recommended**: Consider taking a snapshot before running if you need to preserve the current state

#### After Running

1. If you chose automatic shutdown, the VM will power off in 5 seconds
2. If not, manually shut down the VM
3. In Proxmox web interface, right-click the VM and select "Convert to template"
4. Clone the template to create new VMs with unique identifiers

#### Template Workflow

```
1. Create VM → 2. Install OS → 3. Configure base system
                                    ↓
                              4. Run prepare-template.sh
                                    ↓
                              5. Shutdown VM
                                    ↓
                              6. Convert to template
                                    ↓
                              7. Clone template for new VMs
```

#### What Gets Regenerated on First Boot

When you clone from the template, cloud-init and system services will automatically regenerate:
- Machine ID (`/etc/machine-id`)
- SSH host keys (`/etc/ssh/ssh_host_*`)
- Network configuration (via cloud-init)
- Hostname (via cloud-init)
- User accounts and SSH keys (via cloud-init)

#### Troubleshooting

**Issue**: Cloud-init not running on cloned VMs
- **Solution**: Ensure cloud-init is enabled: `systemctl status cloud-init`

**Issue**: Network interface names changing on clones
- **Solution**: The script removes persistent net rules to prevent this

**Issue**: SSH connection fails after running script
- **Solution**: Expected behavior - SSH keys are removed. Shutdown and convert to template.
