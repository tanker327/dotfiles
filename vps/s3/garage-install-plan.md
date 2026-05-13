# Garage S3 Object Storage — Installation & Configuration Plan

**Dedicated Ubuntu Server · Single Node Deployment**

| | |
|---|---|
| **Author** | Eric |
| **Date** | March 2026 |
| **Target OS** | Ubuntu Server 25.10 |
| **Host** | min-s3 (192.168.10.13) |
| **Storage** | 1.8TB SSD (single disk, LVM, ext4) |
| **Software** | Garage v2.2.0 |
| **License** | AGPL-3.0 (Free) |

---

## 1. Overview

This document provides a step-by-step plan for installing Garage, a lightweight S3-compatible object storage server, on a dedicated Ubuntu Server. Garage is a single-binary Rust application with minimal resource requirements, making it ideal for a purpose-built storage box.

The deployment is a single-node setup with `replication_factor = 1`, optimized for media file storage and general backups accessed over the local network via Tailscale.

### 1.1 Architecture Overview

The target architecture consists of a dedicated box running only the Garage service, accessible to other machines on the Tailscale mesh network and LAN. No Docker is used — Garage runs natively as a systemd service for maximum simplicity and I/O performance.

```
┌─────────────────────────────────────┐
│        S3 Storage Box (min-s3)      │
│      Ubuntu Server 25.10            │
│      IP: 192.168.10.13              │
│                                     │
│  ┌───────────┐    ┌──────────────┐  │
│  │  S3 API   │    │  Admin API   │  │
│  │  :3900    │    │  :3903       │  │
│  └─────┬─────┘    └──────────────┘  │
│        │                            │
│  ┌─────▼──────────────────┐         │
│  │    Garage Engine        │         │
│  │  ┌──────┐  ┌────────┐  │         │
│  │  │ Meta │  │ Block  │  │         │
│  │  │ LMDB │  │ Store  │  │         │
│  │  └──┬───┘  └───┬────┘  │         │
│  └─────┼──────────┼───────┘         │
│        │          │                 │
│   /var/lib/    /mnt/s3data/         │
│   garage/meta  (on 1.8TB SSD)       │
└─────────────────────────────────────┘
         ▲
         │ Tailscale / LAN
         │
    ┌────┴────┐
    │ Clients │  Mac Mini, Proxmox,
    │ boto3   │  rclone, mc, curl
    └─────────┘
```

| Component | Details |
|---|---|
| OS | Ubuntu Server 25.10 |
| Storage Engine | Garage v2.2.0 (native binary) |
| Data Drive | 1.8TB SSD, single disk with LVM (ext4), data stored on `/mnt/s3data` directory |
| Networking | Tailscale mesh + LAN (192.168.10.0/24) |
| Management | garage CLI + AWS CLI / rclone |
| Ports | 3900 (S3 API), 3901 (RPC), 3902 (Web), 3903 (Admin) |

---

## 2. Prerequisites

### 2.1 Hardware

- **Host:** min-s3 — Intel i5-2415M @ 2.3GHz, 4 cores, 7.2GB RAM
- **Disk:** 1.8TB SSD (single disk, LVM volume `ubuntu--vg-ubuntu--lv`, ext4)
- **Network:** Static IP 192.168.10.13 on `enp2s0f0`

### 2.2 Software

Ubuntu Server 25.10 is already installed with static IP configured. The VPS setup script has been run (Docker, Tailscale, Zsh, etc. are installed).

### 2.3 Network

The server should be on the same LAN as other machines, or reachable via Tailscale. No public internet exposure is required.

---

## 3. Installation Steps Summary

| # | Step | Description |
|---|---|---|
| 1 | Prepare the Data Directory | Create /mnt/s3data directory on existing filesystem |
| 2 | Install Garage | Download the v2.2.0 static binary, place in /usr/local/bin |
| 3 | Configure Garage | Create /etc/garage/garage.toml with single-node settings |
| 4 | Create Systemd Service | Set up garage.service with dedicated user and security hardening |
| 5 | Initialize Node Layout | Assign zone and capacity to the node |
| 6 | Create Buckets & Keys | Create media and backups buckets, generate API keys |
| 7 | Connect Tailscale | Tailscale is installed, just authenticate and join tailnet |
| 8 | Test & Verify | Upload/download files using AWS CLI or boto3 |

---

## 4. Detailed Installation

### 4.1 Step 1: Prepare the Data Directory

This server uses a single 1.8TB SSD with LVM. Instead of a separate drive, we create a dedicated directory on the existing filesystem.

```bash
# Create the data directory
sudo mkdir -p /mnt/s3data

# Verify available space (~1.7TB free)
df -h /
```

> **Note:** The data directory lives on the same ext4 filesystem as the OS. This is fine for a single-node deployment. If you add a second disk later, you can mount it at `/mnt/s3data` without changing the Garage config.

---

### 4.2 Step 2: Install Garage Binary

Garage ships as a single static binary with zero dependencies.

```bash
# Download Garage v2.2.0 for x86_64 Linux
wget https://garagehq.deuxfleurs.fr/_releases/v2.2.0/x86_64-unknown-linux-musl/garage

# Make it executable
chmod +x garage

# Move to system path
sudo mv garage /usr/local/bin/

# Verify installation
garage --version
```

---

### 4.3 Step 3: Configure Garage

Create the configuration directory, generate a secure RPC secret, and write the configuration file.

```bash
# Create directories
sudo mkdir -p /etc/garage
sudo mkdir -p /var/lib/garage/meta

# Generate RPC secret (save this output!)
openssl rand -hex 32
```

Create the configuration file:

```bash
sudo nano /etc/garage/garage.toml
```

```toml
metadata_dir = "/var/lib/garage/meta"
data_dir = "/mnt/s3data"
db_engine = "lmdb"

replication_factor = 1

rpc_bind_addr = "0.0.0.0:3901"
rpc_secret = "<PASTE_YOUR_HEX_SECRET_HERE>"

[s3_api]
api_bind_addr = "0.0.0.0:3900"
s3_region = "us-east-1"
root_domain = ".s3.garage.local"

[s3_web]
bind_addr = "0.0.0.0:3902"
root_domain = ".web.garage.local"

[admin]
api_bind_addr = "0.0.0.0:3903"
admin_token = "<PASTE_ANOTHER_HEX_SECRET_HERE>"
```

Generate both secrets with:
```bash
# Generate RPC secret
openssl rand -hex 32

# Generate admin token (use a separate secret)
openssl rand -hex 32
```

> **Note:** `replication_factor = 1` means no redundancy. This is correct for a single-node deployment. Data durability depends entirely on the SSD health. Consider periodic backups of critical data to another location.

---

### 4.4 Step 4: Create Systemd Service

Create a dedicated system user and a systemd unit file for automatic startup and security hardening.

```bash
# Create dedicated user (no login shell)
sudo useradd -r -s /usr/sbin/nologin garage

# Set ownership
sudo chown -R garage:garage /mnt/s3data
sudo chown -R garage:garage /var/lib/garage/meta
sudo chown garage:garage /etc/garage/garage.toml
```

Create the service file:

```bash
sudo nano /etc/systemd/system/garage.service
```

```ini
[Unit]
Description=Garage S3-compatible object storage
After=network.target

[Service]
Type=simple
User=garage
Group=garage
ExecStart=/usr/local/bin/garage -c /etc/garage/garage.toml server
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/mnt/s3data
ReadWritePaths=/var/lib/garage/meta

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable --now garage

# Verify it's running
sudo systemctl status garage
journalctl -u garage -f    # watch logs
```

---

### 4.5 Step 5: Initialize Node Layout

Even for a single-node deployment, Garage requires you to register the node and assign its capacity before it can serve requests.

```bash
# Get the node ID
garage node id
# Output: abcdef1234...@127.0.0.1:3901

# Assign zone and capacity (1700G usable on 1.8TB drive)
garage layout assign -z dc1 -c 1700G <NODE_ID>

# Apply the layout
garage layout apply --version 1
```

> **Note:** Replace `<NODE_ID>` with the hex portion before the `@` symbol from the `garage node id` output.

---

### 4.6 Step 6: Create Buckets & API Keys

Create the storage buckets and generate API credentials for client access.

```bash
# Create buckets
garage bucket create media
garage bucket create backups

# Create an API key
garage key create my-app-key
# ⚠️  SAVE THE OUTPUT — Key ID and Secret key

# Grant read/write access to both buckets
garage bucket allow media --read --write --key my-app-key
garage bucket allow backups --read --write --key my-app-key

# Verify
garage bucket info media
garage key info my-app-key
```

> **Note:** Store the Key ID and Secret key securely. You will need these for every client that connects to the S3 API. Consider creating separate keys for different applications.

---

### 4.7 Step 7: Connect Tailscale

Tailscale is already installed on this server. Just authenticate and join your tailnet.

```bash
# Authenticate and join your tailnet
sudo tailscale up

# Note the Tailscale IP
tailscale ip -4
```

Once connected, the S3 API is reachable from any Tailscale peer at `http://<tailscale-ip>:3900`.

---

### 4.8 Step 8: Test & Verify

#### Using AWS CLI

```bash
# Install AWS CLI
sudo apt install awscli -y

# Configure credentials
aws configure set aws_access_key_id <YOUR_KEY_ID>
aws configure set aws_secret_access_key <YOUR_SECRET_KEY>
aws configure set default.region us-east-1

# Upload a test file
echo 'hello garage' > test.txt
aws s3 cp test.txt s3://media/test.txt \
  --endpoint-url http://<SERVER_IP>:3900

# List objects
aws s3 ls s3://media/ --endpoint-url http://<SERVER_IP>:3900

# Download it back
aws s3 cp s3://media/test.txt /tmp/test-back.txt \
  --endpoint-url http://<SERVER_IP>:3900
```

#### Using Python boto3

```python
import boto3

s3 = boto3.client('s3',
    endpoint_url='http://<SERVER_IP>:3900',
    aws_access_key_id='<YOUR_KEY_ID>',
    aws_secret_access_key='<YOUR_SECRET_KEY>',
    region_name='us-east-1'
)

# Upload
s3.upload_file('photo.jpg', 'media', 'photos/photo.jpg')

# List
for obj in s3.list_objects_v2(Bucket='media')['Contents']:
    print(obj['Key'], obj['Size'])
```

#### Using rclone

```bash
# Install rclone
sudo apt install rclone -y

# Configure remote
rclone config create garage s3 \
  provider Other \
  access_key_id <YOUR_KEY_ID> \
  secret_access_key <YOUR_SECRET_KEY> \
  endpoint http://<SERVER_IP>:3900 \
  region us-east-1

# Sync a directory to S3
rclone sync ~/backups garage:backups/

# List remote contents
rclone ls garage:media/
```

---

## 5. Firewall Configuration

If UFW is enabled, allow only the necessary ports from trusted networks.

```bash
# Allow S3 API from LAN
sudo ufw allow from 192.168.10.0/24 to any port 3900 proto tcp

# Allow S3 API from Tailscale subnet
sudo ufw allow from 100.64.0.0/10 to any port 3900 proto tcp

# Allow admin API from LAN only
sudo ufw allow from 192.168.10.0/24 to any port 3903 proto tcp

# Do NOT expose RPC port (3901) publicly
# Do NOT expose admin port (3903) publicly
```

---

## 6. Monitoring & Health Checks

Garage exposes Prometheus metrics and a health endpoint via the admin API.

```bash
# Health check
curl -s http://localhost:3903/v1/health | python3 -m json.tool

# Prometheus metrics
curl -s http://localhost:3903/metrics

# Check disk usage
df -h /mnt/s3data
df -h /

# Check service status
systemctl status garage
```

> **Tip:** Set up a cron job to alert when disk usage exceeds 80% (data is on root filesystem):
> ```bash
> df / | awk 'NR==2 {if ($5+0 > 80) print "DISK WARNING: "$5" used"}'
> ```

---

## 7. Backup Strategy

With `replication_factor = 1` on a single node, there is no built-in redundancy. If the SSD fails, data is lost.

**Critical data (backups bucket):** Use rclone to sync to a secondary location — a Proxmox node, external USB drive, or cheap cloud tier like Backblaze B2.

**Media files:** If these are replaceable (cached thumbnails, processed outputs), backup may be optional. If they are originals (photos, videos), back them up.

```bash
# Example: nightly sync to a second machine via rclone
# Add to crontab: crontab -e
0 2 * * * rclone sync garage:backups /mnt/backup-drive/garage-backups/
```

---

## 8. Upgrading Garage

```bash
# Download new version
wget https://garagehq.deuxfleurs.fr/_releases/v<NEW_VERSION>/x86_64-unknown-linux-musl/garage
chmod +x garage

# Stop service, replace binary, restart
sudo systemctl stop garage
sudo mv garage /usr/local/bin/garage
sudo systemctl start garage

# Verify
garage --version
sudo systemctl status garage
```

> **Note:** Always check the Garage release notes for breaking changes before upgrading. The metadata database format may change between major versions.

---

## 9. Quick Reference Commands

| Command | Purpose |
|---|---|
| `garage node id` | Show this node's ID |
| `garage status` | Show cluster status |
| `garage bucket list` | List all buckets |
| `garage bucket info <name>` | Show bucket details and permissions |
| `garage bucket create <name>` | Create a new bucket |
| `garage bucket delete <name>` | Delete an empty bucket |
| `garage key list` | List all API keys |
| `garage key create <name>` | Create a new API key |
| `garage key info <name>` | Show key details and permissions |
| `garage layout show` | Show current cluster layout |
| `garage repair --yes tables` | Repair metadata tables |
| `journalctl -u garage -f` | Tail service logs |

---

## 10. Resources

- **Official Documentation:** https://garagehq.deuxfleurs.fr/documentation/
- **Quick Start Guide:** https://garagehq.deuxfleurs.fr/documentation/quick-start/
- **S3 Compatibility:** https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/
- **Community Matrix Chat:** https://matrix.to/#/#garage:deuxfleurs.fr
- **GitHub:** https://github.com/deuxfleurs-org/garage
