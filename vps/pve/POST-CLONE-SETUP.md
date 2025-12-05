# Post-Clone Setup Guide

After cloning a VM from your template in Proxmox VE, follow this workflow to configure each clone efficiently using Cloud-Init. This approach is faster and more reliable than manually editing configuration files.

## Why Use Cloud-Init Configuration?

When you properly configure Cloud-Init settings in the Proxmox UI **before** first boot, the following happens automatically:

- Hostname is set based on the VM name in Proxmox
- Static IP address is configured (no hunting for DHCP addresses)
- SSH public key is injected (passwordless login immediately available)
- Unique SSH host keys are generated
- Disk is resized if you made it larger during clone
- `/etc/hostname` and `/etc/hosts` are automatically updated

## Recommended Workflow

### Step 1: Clone the Template (DO NOT Start Yet)

1. In Proxmox web interface, right-click your template
2. Select **Clone**
3. Configure clone settings:
   - **Target Storage**: Choose storage for the clone
   - **Mode**: Select "Full Clone" (recommended) or "Linked Clone"
   - **Name**: Give it a meaningful name (e.g., `web-server-01`, `db-primary`)
   - **VM ID**: Choose an available ID
4. Click **Clone**
5. **IMPORTANT**: Do NOT start the VM yet!

### Step 2: Configure Cloud-Init Settings

Click on your newly cloned VM in the Proxmox sidebar and navigate to the **Cloud-Init** tab.

Configure the following settings for this specific VM:

#### User Configuration
- **User**: Set username (or leave as template default)
- **Password**: Set password for the user
- **SSH Public Key**: Paste your SSH public key here
  ```bash
  # Get your public key on your local machine:
  cat ~/.ssh/id_ed25519.pub
  # or
  cat ~/.ssh/id_rsa.pub
  ```

#### DNS Configuration
- **DNS Domain**: Set domain if needed (e.g., `local`, `yourdomain.com`)
- **DNS Servers**: Set DNS servers (e.g., `8.8.8.8 1.1.1.1` or your router's IP)

#### Network Configuration (Most Important)
This is where you set the static IP to avoid DHCP hunting:

1. **IP Config (net0)**:
   - Select **IPv4**: `Static`
   - **IPv4/CIDR**: Enter IP with subnet mask (e.g., `192.168.1.50/24`)
   - **Gateway (IPv4)**: Enter gateway IP (e.g., `192.168.1.1`)

2. **IPv6** (optional):
   - Select `SLAAC` for auto-configuration or `Static` for manual
   - Leave as `DHCP` or disabled if not using IPv6

#### Example Configuration
```
User: myuser
Password: (set securely)
SSH Public Key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@laptop

DNS Domain: local
DNS Servers: 8.8.8.8 1.1.1.1

IP Config (net0):
  IPv4: Static
  IPv4/CIDR: 192.168.1.50/24
  Gateway: 192.168.1.1
```

### Step 3: Regenerate Cloud-Init Image

**Critical Step**: After changing any Cloud-Init settings:

1. Click the **Regenerate Image** button at the top of the Cloud-Init tab
2. This forces Proxmox to write your settings to the Cloud-Init ISO image
3. Without this step, your changes may not take effect

### Step 4: First Boot

Now you can start the VM:

1. Click **Start** in the Proxmox UI
2. The VM will boot and Cloud-Init will automatically:
   - Set hostname from VM name (e.g., `web-server-01`)
   - Configure static IP address
   - Update `/etc/hostname` and `/etc/hosts`
   - Inject SSH public key to `~/.ssh/authorized_keys`
   - Generate unique SSH host keys
   - Resize root filesystem if disk was enlarged
   - Create user with configured password

3. Wait 30-60 seconds for first boot to complete

### Step 5: Connect via SSH

```bash
# Connect using the static IP you configured
ssh myuser@192.168.1.50

# Or using the hostname (if DNS is configured)
ssh myuser@web-server-01.local
```

You should be able to log in immediately without a password (using your SSH key).

## Comparison: Manual vs Cloud-Init Method

| Task | Manual Method (Slow) | Cloud-Init Method (Recommended) |
|------|---------------------|--------------------------------|
| **Hostname** | SSH in, edit `/etc/hostname` and `/etc/hosts` manually | Automatically set from VM name in Proxmox |
| **IP Address** | Random DHCP (hard to find) or manual netplan edit | Set static IP in Proxmox UI before boot |
| **SSH Access** | Use password initially, manually add keys later | SSH key injected automatically, passwordless from start |
| **Speed** | Slow (requires login, typing, reboots) | Instant (configure in UI, then boot) |
| **Errors** | Prone to typos in config files | UI-validated, less error-prone |

## Troubleshooting

### Issue: Changes Not Applied on First Boot
**Solution**: Make sure you clicked "Regenerate Image" after changing Cloud-Init settings.

### Issue: Cannot SSH to Static IP
**Troubleshooting steps**:
1. Verify IP is accessible: `ping 192.168.1.50`
2. Check VM console in Proxmox to see if boot completed
3. Verify Cloud-Init ran: Check VM console for cloud-init output
4. Verify static IP was applied: Log in via console, run `ip addr show`

### Issue: SSH Key Not Working
**Solution**:
1. Verify you pasted the correct public key (should start with `ssh-ed25519` or `ssh-rsa`)
2. Try connecting with password first: `ssh -o PreferredAuthentications=password myuser@192.168.1.50`
3. Check authorized_keys: `cat ~/.ssh/authorized_keys`

### Issue: Hostname Not Set Correctly
**Solution**:
1. Cloud-Init sets hostname from VM name in Proxmox
2. To change: Shutdown VM, rename in Proxmox, regenerate cloud-init image, restart
3. Or manually: `sudo hostnamectl set-hostname new-name`

### Issue: Network Not Working After Boot
**Troubleshooting**:
1. Check Cloud-Init logs: `sudo cat /var/log/cloud-init.log`
2. Verify network config: `cat /etc/netplan/50-cloud-init.yaml`
3. Test connectivity: `ping 8.8.8.8` (Google DNS)
4. Check gateway: `ip route show`

## Advanced: Bulk Cloning

If you're creating multiple VMs with similar configurations:

1. Clone first VM and configure Cloud-Init settings
2. For subsequent clones, you can script this using Proxmox API:
   ```bash
   # Example using pvesh
   pvesh create /nodes/pve/qemu/100/clone -newid 101 -name web-server-02
   pvesh set /nodes/pve/qemu/101/config -ipconfig0 ip=192.168.1.51/24,gw=192.168.1.1
   ```

3. Or use Terraform with Proxmox provider for infrastructure-as-code

## Tips for Success

1. **Always regenerate** after changing Cloud-Init settings
2. **Use static IPs** for servers/services that other machines need to find
3. **Document your IPs** - Keep a spreadsheet of VM names and their assigned IPs
4. **SSH keys over passwords** - Much more secure and convenient
5. **Test the template** - Clone a test VM first to verify everything works
6. **Keep template updated** - Periodically update packages in template and re-prepare

## Next Steps

After your VM is running:

1. Verify all services are running correctly
2. Update packages if needed: `sudo apt update && sudo apt upgrade`
3. Install application-specific software
4. Configure firewall rules if needed
5. Set up monitoring/backups

## Related Documentation

- [prepare-template.sh](./prepare-template.sh) - Script to prepare VMs for templating
- [README.md](./README.md) - Main documentation for PVE scripts
- [Proxmox Cloud-Init Documentation](https://pve.proxmox.com/wiki/Cloud-Init_Support)
