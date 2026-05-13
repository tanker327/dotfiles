# Cloud-Init Template Guide

A practical reference for building, maintaining, and using high-quality
Cloud-Init templates on Proxmox VE. Focuses on the things that aren't obvious
from the official wiki — the "wish I'd known this when I started" notes.

> See also:
> - [`prepare-template.sh`](./prepare-template.sh) — the in-VM cleanup script for the "boot installer → clean → templatize" workflow
> - [`POST-CLONE-SETUP.md`](./POST-CLONE-SETUP.md) — how to configure each clone after creation
> - [Proxmox Cloud-Init Wiki](https://pve.proxmox.com/wiki/Cloud-Init_Support)

## Table of Contents

- [Why bother?](#why-bother)
- [Mental model](#mental-model)
- [Two workflows](#two-workflows)
- [Workflow A: Cloud image + virt-customize (recommended)](#workflow-a-cloud-image--virt-customize-recommended)
- [Workflow B: Installer ISO + prepare-template.sh](#workflow-b-installer-iso--prepare-templatesh)
- [VM size tiers](#vm-size-tiers)
- [Cloud-init knobs reference](#cloud-init-knobs-reference)
- [15 tips for better templates](#15-tips-for-better-templates)
- [Custom user-data snippets](#custom-user-data-snippets)
- [Versioning and lifecycle](#versioning-and-lifecycle)
- [Troubleshooting](#troubleshooting)

## Why bother?

Without a template:
- Every new VM means 10+ minutes of clicking through the Ubuntu installer
- Each VM ends up slightly different (forgot to install qemu-guest-agent on
  that one, set a different timezone on this one)
- SSH keys, hostnames, users all set manually
- No way to spin up a new VM in under a minute

With a cloud-init template:
- `qm clone + qm set + qm start` → SSH-ready VM in ~30 seconds
- Every VM starts from an identical, known-good base
- Per-VM config (user, IP, SSH keys, hostname, packages) declarative
- Automation-friendly — entire fleet rebuildable from scripts

## Mental model

Two very different "Ubuntu images":

| Type | File name | Use |
|---|---|---|
| **Installer ISO** | `ubuntu-26.04-live-server-amd64.iso` (~3 GB) | Boot → installer asks questions → installs Ubuntu. **Not** cloud-init-friendly out of the box. |
| **Cloud image** | `ubuntu-26.04-server-cloudimg-amd64v3.img` (~600 MB) | Pre-installed minimal Ubuntu, designed for cloud-init. **This is what you want for templates.** |

Cloud images live at:
- Ubuntu: <https://cloud-images.ubuntu.com/releases/26.04/release/>
- Debian: <https://cloud.debian.org/images/cloud/>

### amd64 vs amd64v3

Ubuntu publishes two server cloud images per release:

| Variant | Target | Compatible CPUs |
|---|---|---|
| `ubuntu-26.04-server-cloudimg-amd64.img` | baseline x86-64 | any x86-64 CPU since 2003 |
| `ubuntu-26.04-server-cloudimg-amd64v3.img` | x86-64-v3 microarch level | Intel Haswell (2013+) / AMD Zen (2017+) and newer |

**Use `amd64v3` if your host CPU supports it** — same Ubuntu, but glibc / OpenSSL / many libraries are compiled with AVX2, BMI1/2, FMA, etc. Expect 5–15% wins in CPU-bound code paths, no install changes, no downsides on supported hardware.

Verify support on the PVE host:

```bash
/usr/lib64/ld-linux-x86-64.so.2 --help | grep 'x86-64-v'
```

If you see `x86-64-v3 (supported, searched)`, you're good. Any modern AMD Ryzen, Intel 4th gen Core or newer, and most server CPUs from the last decade support it. This guide uses `amd64v3` throughout — if you're on older hardware, swap the filename for `amd64`.

The cloud image was booted once on Canonical's build farm to install a minimal
system, then frozen. You import it as a disk, attach a cloud-init drive, and
on first boot cloud-init configures it according to the settings you set in
Proxmox.

## Two workflows

**A. Cloud image + `virt-customize` (recommended)**
- Download a cloud image, customize it offline without booting, import as template
- Faster to build, more reproducible, no manual installer steps
- Right answer for almost everyone

**B. Installer ISO + `prepare-template.sh`**
- Install Ubuntu via the installer the normal way, configure manually, then
  run [`prepare-template.sh`](./prepare-template.sh) to clean up before templating
- Useful when you need a non-standard install (custom partitioning, encrypted
  disks, specific kernel) or when no suitable cloud image exists
- More manual but full control

You can have both. Most people end up with one cloud-image template per
distro and the occasional ISO-based template for special cases.

## Workflow A: Cloud image + virt-customize (recommended)

One-time setup, then reusable forever.

### Prerequisites (on the Proxmox host)

```bash
apt install -y libguestfs-tools
```

`virt-customize` lets you modify a disk image without booting it — install
packages, run commands, clear identity, all offline.

### Step 1 — Download the cloud image

```bash
cd /var/lib/vz/template/iso/
wget https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64v3.img
```

### Step 2 — Pre-bake (keep it minimal)

Keep the template lean. The template is the **base** — everything beyond a working Ubuntu that cloud-init can configure should come from [`setup-vps.sh`](../setup-vps.sh) after the VM boots. That gives you:

- **One source of truth** for "what's installed" — `setup-vps.sh`
- **A clean template** that boots fast and doesn't drift from the install script
- **Component choice per VM** — `setup-vps.sh` asks which components you want; one VM gets Docker, another doesn't

So pre-bake only handles the parts cloud-init / Proxmox actually need to function. Everything else — Docker, Tailscale, dev tools, Oh My Zsh, dotfiles — runs from `setup-vps.sh` on first SSH.

```bash
IMG=/var/lib/vz/template/iso/ubuntu-26.04-server-cloudimg-amd64v3.img

virt-customize -a "$IMG" \
  --install qemu-guest-agent,ca-certificates,curl \
  --run-command 'systemctl enable qemu-guest-agent' \
  --run-command 'systemctl enable serial-getty@ttyS0.service' \
  --truncate /etc/machine-id \
  --delete /var/lib/dbus/machine-id \
  --run-command 'rm -f /etc/ssh/ssh_host_*' \
  --firstboot-command 'dpkg-reconfigure openssh-server' \
  --write '/etc/cloud/cloud.cfg.d/99_pve.cfg:datasource_list: [ NoCloud, ConfigDrive ]'
```

What each line does:

- `--install qemu-guest-agent,ca-certificates,curl` — agent is required for PVE to see the IP and quiesce snapshots; `curl` + `ca-certificates` lets the first thing a user does (`curl ... setup-vps.sh | sudo bash`) actually work.
- `--run-command 'systemctl enable qemu-guest-agent'` — must be enabled in the guest, not just in PVE.
- `--run-command 'systemctl enable serial-getty@ttyS0.service'` — serial console works on first boot (your lifeline when SSH breaks).
- `--truncate /etc/machine-id` + `--delete /var/lib/dbus/machine-id` — every clone generates its own machine-id on first boot (critical — see [Tip 6](#tip-6-critical-clear-machine-id-and-ssh-host-keys)).
- `--run-command 'rm -f /etc/ssh/ssh_host_*'` — same idea for SSH host keys.
- `--firstboot-command 'dpkg-reconfigure openssh-server'` — regenerates SSH host keys on first boot of each clone.
- `--write /etc/cloud/cloud.cfg.d/99_pve.cfg` — restricts cloud-init to NoCloud/ConfigDrive sources; kills 60–90s of AWS/Azure metadata probing on every boot.

That's it. The pre-bake adds maybe ~20 MB to the cloud image. Template stays under ~850 MB.

#### Why not bake Docker/Tailscale/dev tools into the template?

It's tempting, but:

- **`setup-vps.sh` is the source of truth.** Pre-baking duplicates that logic in two places — they drift, you forget which is which.
- **Components are choices.** Not every VM needs Docker. Not every VM needs Tailscale. `setup-vps.sh` asks; the template shouldn't decide.
- **The savings aren't huge.** 60–90s of `apt install` on first boot beats a 1.4 GB template that drifts from your install script over time.

If you find yourself running `setup-vps.sh` with the same answers every time, that's a signal to either (a) automate the prompts via env vars and pipe answers, or (b) extract a role-specific cloud-init `runcmd` — not to bloat the template.

### Step 3 — Create the template VM

```bash
VMID=9000

qm create $VMID \
  --name tmpl-ubuntu-26.04-cloudinit \
  --memory 2048 --balloon 0 \
  --cores 2 --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single \
  --agent enabled=1 \
  --ostype l26 \
  --serial0 socket --vga serial0 \
  --tags template,ubuntu,2604

# Import the customized cloud image as the boot disk
qm set $VMID --scsi0 local-lvm:0,import-from=/var/lib/vz/template/iso/ubuntu-26.04-server-cloudimg-amd64v3.img,discard=on,ssd=1,iothread=1,cache=none

# Cloud-init drive — where cloud-init reads its config from
qm set $VMID --ide2 local-lvm:cloudinit

# Boot from the disk
qm set $VMID --boot order=scsi0

# Pre-set SSH key so every clone inherits it (override per-VM with qm set --sshkey if you want)
qm set $VMID --sshkey /root/.ssh/authorized_keys

# Description for future-you
qm set $VMID --description "Ubuntu 26.04 cloud-init template
Built: $(date +%Y-%m-%d)
Source: cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64v3.img
Baked: qemu-guest-agent, curl, git, vim, htop, tmux, zsh, unzip
Default user: set via --ciuser on clone
Use: qm clone $VMID <new-id> --name <name>; qm resize <id> scsi0 <size>G"

# Convert to template (locks it; clones from here)
qm template $VMID

# Protect against accidental destroy
qm set $VMID --protection 1
```

> **Note on UEFI vs BIOS**: Ubuntu cloud images are built for BIOS by default.
> The example above uses Proxmox defaults (i440fx + SeaBIOS) — simpler and
> trouble-free. If you specifically need UEFI (Secure Boot, certain PCIe
> passthrough scenarios), add `--machine q35 --bios ovmf --efidisk0
> local-lvm:1,format=raw,efitype=4m,pre-enrolled-keys=0` but expect occasional
> boot quirks.

### Step 4 — Test the template with a throwaway clone

Always validate before relying on it:

```bash
qm clone 9000 999 --name test-clone
qm set 999 --protection 0 --ciuser ericwu --ipconfig0 ip=dhcp
qm start 999

# Wait 30 seconds, get IP from Proxmox UI or:
qm guest cmd 999 network-get-interfaces 2>/dev/null | grep -A1 ip-address

# Try SSH
ssh ericwu@<ip-from-above>

# If it works:
qm stop 999 && qm destroy 999 --purge --destroy-unreferenced-disks 1
```

A 60-second test now beats finding a typo at the worst possible moment later.

> **Note**: the `--protection 0` on the clone is intentional. Some Proxmox
> versions copy the template's `protection: 1` flag into the clone, which
> then refuses `qm destroy`. Clearing it explicitly makes cleanup just work.
> If you ever see *"cannot remove VM 999 - protection mode enabled"*, run
> `qm set <vmid> --protection 0` first.

### Step 5 — Clone for real

For every new VM:

```bash
TEMPLATE=9000
NEW_VMID=113
NEW_NAME=db-prod

qm clone $TEMPLATE $NEW_VMID --name $NEW_NAME

# Grow the disk from the cloud image's ~3.5G to whatever you want
qm resize $NEW_VMID scsi0 +97G   # adds 97G → ~100G total

# Per-VM config
qm set $NEW_VMID \
  --ciuser ericwu \
  --ipconfig0 ip=dhcp \
  --nameserver 1.1.1.1 \
  --memory 4096 --cores 4

qm start $NEW_VMID
```

~30 seconds later you can `ssh ericwu@<ip>`. Done.

## Workflow B: Installer ISO + prepare-template.sh

When you need full control over the install:

1. Create a VM from an installer ISO (see [POST-CLONE-SETUP.md](./POST-CLONE-SETUP.md) for VM creation params)
2. Boot it, run through the installer, configure manually
3. SSH in and run [`prepare-template.sh`](./prepare-template.sh):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/tanker327/dotfiles/master/vps/pve/prepare-template.sh | sudo bash
   ```
4. Script cleans machine-id, SSH host keys, logs, cloud-init state, and shuts down the VM
5. Convert to template: `qm template <vmid>`
6. Clone as in Workflow A from Step 4 onwards

The script handles all the same identity-clearing that `virt-customize`
does in Workflow A — just done from inside the running VM instead of offline.

## VM size tiers

"Regular VM" means different things. Here's a tiered set of defaults to pick
from. All assume the cloud-init template (VMID 9000) is the base; clones
override `--cores`, `--memory`, and disk size.

### Tier table

| Tier | Use case | vCPU | RAM | Disk |
|---|---|---|---|---|
| **Tiny** | DNS, agent, single-purpose daemon | 1 | 1 GB | 16 GB |
| **Small** ⭐ | App server, API, "give me a Linux box" | 2 | 2 GB | 30 GB |
| **Medium** | Dev VM, side project, single-user service | 4 | 4 GB | 50 GB |
| **Large** | CI runner, build server, multi-service | 8 | 8 GB | 100 GB |

⭐ **Small** is the right default if you can't decide. Almost always enough;
bump if proven necessary, shrink if measured. Resizing CPU/RAM is hot-pluggable
on virtio; disk grow requires `growpart + resize2fs` inside the guest.

### Universal settings (bake into the template)

Apply these to **every** VM via the template — every clone inherits them.

| Setting | Value | Why |
|---|---|---|
| `--cpu host` | host passthrough | All host CPU features available; best perf on single-host setups |
| `--balloon 0` | off | Ballooning steals memory unpredictably under load |
| `--scsihw virtio-scsi-single` | virtio-scsi-single | Best perf, iothread support |
| disk options | `cache=none,discard=on,ssd=1,iothread=1` | DB-safe fsync, TRIM works, perf |
| `--agent enabled=1` | on | PVE shows IPs, clean shutdowns, snapshot quiesce |
| `--onboot 1` | on | Comes back after host reboot |
| `--net0` | `virtio,bridge=vmbr0` | Paravirt is ~10× faster than e1000 |
| `--ostype l26` | `l26` | Linux 2.6+; tells QEMU what HW to emulate |

### Per-VM settings (set on every clone)

| Setting | Why per-VM |
|---|---|
| `--cores`, `--memory` | Workload-dependent (see tier table) |
| Disk size | Workload-dependent |
| `--ciuser`, `--sshkey` | Per-user / per-role |
| `--ipconfig0` | DHCP usually; static for things you need to find reliably (DB, monitoring, gateway) |
| `--cicustom` | Role snippet — see [Custom user-data snippets](#custom-user-data-snippets) |
| `--tags` | Searchability — e.g. `prod,db` or `dev,scratch` |

### Per-tier clone commands

Drop in your `NEWID` and `NAME`. Disk resize uses `+NG` where N = target GB
minus the ~4 GB cloud-image base.

```bash
# ----- TINY: 1 vCPU / 1 GB / 16 GB
qm clone 9000 NEWID --name NAME
qm resize NEWID scsi0 +12G
qm set NEWID --cores 1 --memory 1024 --balloon 0 \
  --ciuser ericwu --ipconfig0 ip=dhcp
qm start NEWID

# ----- SMALL (default): 2 vCPU / 2 GB / 30 GB
qm clone 9000 NEWID --name NAME
qm resize NEWID scsi0 +26G
qm set NEWID --cores 2 --memory 2048 --balloon 0 \
  --ciuser ericwu --ipconfig0 ip=dhcp
qm start NEWID

# ----- MEDIUM: 4 vCPU / 4 GB / 50 GB
qm clone 9000 NEWID --name NAME
qm resize NEWID scsi0 +46G
qm set NEWID --cores 4 --memory 4096 --balloon 0 \
  --ciuser ericwu --ipconfig0 ip=dhcp
qm start NEWID

# ----- LARGE: 8 vCPU / 8 GB / 100 GB
qm clone 9000 NEWID --name NAME
qm resize NEWID scsi0 +96G
qm set NEWID --cores 8 --memory 8192 --balloon 0 \
  --ciuser ericwu --ipconfig0 ip=dhcp
qm start NEWID
```

### Capacity planning (formula)

Pick a target headroom for the host itself, then divide what's left across
your concurrent running VMs.

```
host_total_ram    = <total RAM, GB>
host_reserve      = 8 GB    # for PVE + ZFS ARC + page cache + headroom
allocatable_ram   = host_total_ram - host_reserve

max_running_VMs  ≈ allocatable_ram / avg_vm_ram
```

Examples on a 96 GB host:
- Reserve 8 GB → 88 GB allocatable
- **Small** (2 GB each) → up to ~44 concurrent VMs
- **Medium** (4 GB each) → up to ~22
- **Large** (8 GB each) → up to ~11

CPU is far less of a constraint. 2–3× overcommit on vCPUs is comfortable for
typical workloads; only pin / reserve cores for latency-sensitive guests (DBs
under heavy load, real-time stuff).

Disk: thin provisioning means you pay only for what's written. Watch the
thin-pool fill ratio more carefully than per-VM disk sizes — going over the
physical disk corrupts every guest.

### What to make static, not DHCP

Set a static IP via `--ipconfig0 ip=<cidr>,gw=<gw>` for VMs you need to find
reliably:

- Database servers
- Reverse proxies / ingress
- DNS servers
- Monitoring / log collectors
- Anything in DNS or in another VM's config

DHCP is fine for everything else (CI runners, scratch VMs, devboxes) — saves
you the friction of allocating IPs.

## Cloud-init knobs reference

Set these per-clone with `qm set <id> <flag>`:

| Flag | Purpose | Example |
|---|---|---|
| `--ciuser <name>` | Username to create on first boot | `--ciuser ericwu` |
| `--cipassword <pw>` | Set user password (omit if using SSH keys) | `--cipassword 'changeme'` |
| `--sshkey <file>` | Path to file with one or more public keys | `--sshkey ~/.ssh/authorized_keys` |
| `--ipconfig0 ip=dhcp` | DHCP for net0 | `--ipconfig0 ip=dhcp` |
| `--ipconfig0 ip=...,gw=...` | Static IP | `--ipconfig0 ip=192.168.10.50/24,gw=192.168.10.1` |
| `--nameserver <ip>` | DNS server(s), space-separated | `--nameserver "1.1.1.1 8.8.8.8"` |
| `--searchdomain <d>` | DNS search domain | `--searchdomain home.lan` |
| `--cicustom user=...` | Custom user-data YAML | `--cicustom "user=local:snippets/role-db.yaml"` |
| `--citype` | Cloud-init flavor | `--citype nocloud` (default; correct for Proxmox) |

To see what cloud-init will hand to the VM on next boot:

```bash
qm cloudinit dump <vmid> user
qm cloudinit dump <vmid> network
qm cloudinit dump <vmid> meta
```

## 15 tips for better templates

### Tip 1: Pre-bake common packages with virt-customize

**Why**: `apt install` on every clone's first boot is slow and bandwidth-heavy.
Baking packages into the template image means every clone is instantly ready.

Covered in [Workflow A, Step 2](#step-2--pre-bake-everything-into-the-image).

### Tip 2: Use a separate VMID range for templates

Pick a range like `9000-9099` for templates, `100-999` for actual VMs. Templates
sort together in the UI, no risk of accidentally `qm destroy`-ing a template
because you typoed the VMID.

### Tip 3: Pin CPU type intentionally

- `--cpu host` — passes through all host CPU features. Best perf, single-host only.
- `--cpu x86-64-v3` — portable across modern x86 hosts; required if you might cluster.

For a single Proxmox host, **always `--cpu host`**. The default `kvm64` is a
performance regression for no benefit.

### Tip 4: Enable QEMU guest agent on both sides

Both must be true:
- PVE side: `--agent enabled=1` on the VM config
- Guest side: `qemu-guest-agent` package installed AND `systemctl enable qemu-guest-agent`

Without the guest piece, `qm shutdown` falls back to ACPI (slow, ungraceful),
the PVE UI never shows the VM's IP, and snapshots can't quiesce filesystems.

Workflow A bakes both in. Workflow B's `prepare-template.sh` installs the
package; make sure it's also enabled.

### Tip 5: Pre-wire your SSH key on the template

Instead of `--sshkey` on every clone:

```bash
qm set 9000 --sshkey /root/.ssh/authorized_keys
```

Cloned VMs inherit it. You can still override per-VM with another `--sshkey`
call before starting.

### Tip 6: **CRITICAL** — clear machine-id and SSH host keys

Cloud images and installed VMs carry identity files that **must not** be cloned:

- `/etc/machine-id` — used by systemd-journald, DHCP client (RFC 4361), and others. Two VMs with the same machine-id will fight over DHCP leases and corrupt each other's journal.
- `/var/lib/dbus/machine-id` — same purpose, sometimes a symlink to the above.
- `/etc/ssh/ssh_host_*` — if cloned, every VM has the same SSH host fingerprint. `ssh` will warn loudly and refuse to connect once you start adding entries to `known_hosts`.

Workflow A (`virt-customize`):
```bash
--truncate /etc/machine-id \
--delete /var/lib/dbus/machine-id \
--run-command 'rm -f /etc/ssh/ssh_host_*' \
--firstboot-command 'dpkg-reconfigure openssh-server'
```

Workflow B: handled by [`prepare-template.sh`](./prepare-template.sh).

Both produce fresh per-VM identities on first boot.

### Tip 7: Make serial console actually work

You set `--serial0 socket --vga serial0` on the VM. But the *guest* also needs
`getty` enabled on `ttyS0` or the console stays blank:

```bash
virt-customize -a <image> \
  --run-command 'systemctl enable serial-getty@ttyS0.service'
```

Test from the PVE host:
```bash
qm terminal <vmid>
```

If you see a login prompt, perfect. This is your lifeline when the network is
broken or the VM is half-booted.

### Tip 8: Keep the template disk small, resize per clone

The cloud image is ~3.5 GB. **Don't resize the template** — leave it small.
Resize per-clone:

```bash
qm clone 9000 113 --name db-prod
qm resize 113 scsi0 +97G   # adds 97G to the existing 3-4G base
```

Linked clones from a small template are also faster.

### Tip 9: Skip UEFI for Linux cloud images (unless you need it)

Most Ubuntu/Debian cloud images are built for BIOS. Going UEFI works but adds
a 4 MB EFI disk per VM and occasional first-boot weirdness with cloud-init.

Default (recommended for Linux cloud images): `i440fx` + SeaBIOS. Drop:
- `--machine q35 --bios ovmf`
- `--efidisk0 local-lvm:1,format=raw,...`

Keep UEFI **only** if you specifically need Secure Boot, certain PCIe
passthrough scenarios, or Windows guests.

### Tip 10: Tag your templates

```bash
qm set 9000 --tags template,ubuntu,2604,base
```

Searchable in the UI and CLI:
```bash
qm list --filter tags=template
```

Trivial to add, huge ergonomics win when you have 30+ VMs.

### Tip 11: Lock the template against accidental destroy

```bash
qm set 9000 --protection 1
```

`qm destroy 9000` will refuse without `--purge --force`. Cheap insurance,
especially if you have tab-completion habits.

### Tip 12: Organize cloud-init snippets by role

Don't write one giant `userdata.yaml`. Make role-based snippets:

```
/var/lib/vz/snippets/
├── base-user.yaml           # SSH keys, user, agent — applies to ALL VMs
├── role-db.yaml             # postgres prep
├── role-docker.yaml         # docker.io + buildx + compose
└── role-claude-agent.yaml   # node, claude code CLI
```

Each role file is small and reviewable. Compose per VM:

```bash
qm set 113 --cicustom "user=local:snippets/role-db.yaml"
```

Enable snippets on `local` storage (one-time):

```bash
pvesm set local --content iso,backup,vztmpl,snippets
```

Or via the UI: Datacenter → Storage → local → Edit → tick "Snippets".

See [Custom user-data snippets](#custom-user-data-snippets) below for examples.

### Tip 13: Always test the template with a throwaway clone

```bash
qm clone 9000 999 --name test-clone
qm set 999 --protection 0 --ciuser ericwu --ipconfig0 ip=dhcp
qm start 999
# verify SSH works, then:
qm stop 999 && qm destroy 999 --purge --destroy-unreferenced-disks 1
```

60 seconds of pre-flight beats finding a typo when you're trying to spin up a
real VM under pressure.

### Tip 14: Version your templates instead of mutating them

When Ubuntu 26.04.1 ships, **don't** rebuild VMID 9000 in place. Create 9001
as the new version. Keep 9000 around (rename to `tmpl-ubuntu-26.04.0-deprecated`).

- Old VMs you might need to recreate still rebuild from the version they were born from
- New VMs get the new base
- Easy rollback if 9001 has a regression
- Once you're confident, `qm set 9000 --protection 0 && qm destroy 9000`

### Tip 15: Document the template in its description

```bash
qm set 9000 --description "$(cat <<'EOF'
Ubuntu 26.04 cloud-init template
Built: 2026-05-13
Source: cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64v3.img
Baked packages: qemu-guest-agent, curl, git, vim, htop, tmux, zsh, unzip
SSH keys: /root/.ssh/authorized_keys on PVE host
Default user: set via --ciuser on clone
Use:
  qm clone 9000 <new-id> --name <name>
  qm resize <new-id> scsi0 +97G
  qm set <new-id> --ciuser <user> --ipconfig0 ip=dhcp
  qm start <new-id>
EOF
)"
```

Future-you in 6 months will thank you.

## Custom user-data snippets

Beyond basic cloud-init flags, you can supply a full YAML user-data file that
runs on first boot: install packages, write config files, run commands, etc.

### Setup

```bash
# Enable snippets on local storage (one-time)
pvesm set local --content iso,backup,vztmpl,snippets

# Snippet directory:
ls /var/lib/vz/snippets/
```

### Example: base user setup (`base-user.yaml`)

```yaml
#cloud-config
users:
  - name: ericwu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: [sudo, docker]
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... ericwu@laptop

# Disable root SSH login
disable_root: true

# Set timezone (cloud-init handles this nicely)
timezone: America/Los_Angeles

# Install packages on first boot (or pre-bake in the image — see Tip 1)
package_update: true
packages:
  - qemu-guest-agent
  - git
  - curl
  - tmux
  - htop

# Run on first boot only
runcmd:
  - systemctl enable --now qemu-guest-agent
  - sudo -u ericwu git clone https://github.com/tanker327/dotfiles.git /home/ericwu/dotfiles

# Reboot at end of cloud-init (rarely needed)
# power_state:
#   mode: reboot
#   timeout: 30
#   condition: True
```

Attach to a VM:

```bash
qm set 113 --cicustom "user=local:snippets/base-user.yaml"
```

### Example: db role on top of base (`role-db.yaml`)

```yaml
#cloud-config
users:
  - name: ericwu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: [sudo]
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... ericwu@laptop

package_update: true
packages:
  - git
  - curl
  - qemu-guest-agent

write_files:
  - path: /etc/motd
    content: |
      ┌─────────────────────────────┐
      │  PostgreSQL Production VM   │
      │  Managed by cloud-init      │
      └─────────────────────────────┘

runcmd:
  - systemctl enable --now qemu-guest-agent
  - sudo -u ericwu git clone https://github.com/tanker327/dotfiles.git /home/ericwu/dotfiles
  # Note: vps/db/setup-postgres.sh is interactive. Run it manually after first SSH
  # rather than from cloud-init, unless you adapt it to take env vars.
```

### Multiple snippets — composition

Cloud-init doesn't natively merge multiple user-data files. Two approaches:

1. **One file per role** — duplicate the base bits. Simple, no magic.
2. **Use `#include` with HTTP-served snippets** — your snippet says `#include https://.../base.yaml` plus role-specific bits. Powerful but needs an HTTP server.

For a personal homelab, option 1 is fine.

### Debugging cloud-init failures inside a VM

```bash
# Did it run?
cloud-init status --long

# What did it actually do?
sudo less /var/log/cloud-init.log
sudo less /var/log/cloud-init-output.log

# Re-run from scratch (DESTRUCTIVE — re-creates user, re-runs all modules)
sudo cloud-init clean --logs --reboot
```

## Versioning and lifecycle

Recommended naming convention for templates:

| VMID | Name | Status |
|---|---|---|
| 9000 | `tmpl-ubuntu-26.04.0-cloudinit` | Active (current) |
| 9001 | `tmpl-ubuntu-26.04.1-cloudinit` | Active (newer) |
| 8999 | `tmpl-ubuntu-24.04-cloudinit-deprecated` | Keep for legacy clones |

Rebuild cadence:
- **Monthly**: rebuild active templates to pick up latest security updates
- **On point release** (26.04.0 → 26.04.1): make a new VMID, don't mutate
- **On major release** (26.04 → 28.04): new VMID range or clearer naming

When you rebuild, repeat the [Workflow A](#workflow-a-cloud-image--virt-customize-recommended) steps. Total time: ~5 minutes.

## Troubleshooting

### Cloned VM has same MAC address as another

Proxmox generates a new MAC on clone — but only on `--full` clones. Linked
clones share the original. If you must use linked clones and see this, force
a regenerate:

```bash
qm set <vmid> --net0 virtio,bridge=vmbr0,macaddr=auto
```

### Cloud-init doesn't apply settings on first boot

Check, in order:

1. `qm config <vmid>` shows the cloud-init drive (`ide2: local-lvm:cloudinit`)
2. `qm cloudinit dump <vmid> user` returns sensible YAML
3. Inside the VM: `sudo cloud-init status --long` — if it says `disabled`, the
   image was built without cloud-init enabled. Reinstall with
   `apt install cloud-init` and re-bake.
4. Inside the VM: `sudo less /var/log/cloud-init.log` for actual errors

### SSH connection fails right after clone

Three common causes:
- **Wrong known_hosts**: prior VM had the same IP / hostname. `ssh-keygen -R <host-or-ip>`.
- **Host keys not regenerated**: the template didn't clear them. Confirm with `sudo ssh-keygen -A` inside the VM and verify `/etc/ssh/ssh_host_*` mtimes are recent.
- **SSH not yet ready**: wait 30s after `qm start`. Cloud-init runs before sshd is fully up.

### "Bad reserved field" / cloud-init takes 90+ seconds

cloud-init is probing AWS/Azure/GCE metadata endpoints that don't exist in
your homelab. Fix by restricting to the NoCloud datasource:

```bash
cat > /etc/cloud/cloud.cfg.d/99_pve.cfg <<'EOF'
datasource_list: [ NoCloud, ConfigDrive ]
EOF
```

`prepare-template.sh` does this for you in Workflow B. For Workflow A, add via
`virt-customize`:

```bash
virt-customize -a "$IMG" \
  --write '/etc/cloud/cloud.cfg.d/99_pve.cfg:datasource_list: [ NoCloud, ConfigDrive ]'
```

### Disk doesn't expand to full size after resize

The Ubuntu cloud image includes `cloud-initramfs-growroot` which auto-grows
on first boot. If not:

```bash
sudo growpart /dev/sda 1
sudo resize2fs /dev/sda1   # or xfs_growfs / for XFS
```

### Want to start fresh and re-run cloud-init

```bash
sudo cloud-init clean --logs
sudo rm -rf /var/lib/cloud/
sudo reboot
```

DESTRUCTIVE — re-creates the user, re-runs `runcmd`, etc. Use only on test VMs.

## Quick reference: build a new template from scratch

```bash
# On the Proxmox host

# 1. Get the cloud image
cd /var/lib/vz/template/iso/
wget https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64v3.img

# 2. Pre-bake (minimal — just identity clears + agent + cloud-init pinning)
apt install -y libguestfs-tools  # one-time
IMG=$(pwd)/ubuntu-26.04-server-cloudimg-amd64v3.img
virt-customize -a "$IMG" \
  --install qemu-guest-agent,ca-certificates,curl \
  --run-command 'systemctl enable qemu-guest-agent' \
  --run-command 'systemctl enable serial-getty@ttyS0.service' \
  --truncate /etc/machine-id \
  --delete /var/lib/dbus/machine-id \
  --run-command 'rm -f /etc/ssh/ssh_host_*' \
  --firstboot-command 'dpkg-reconfigure openssh-server' \
  --write '/etc/cloud/cloud.cfg.d/99_pve.cfg:datasource_list: [ NoCloud, ConfigDrive ]'

# 3. Build the template VM
VMID=9000
qm create $VMID \
  --name tmpl-ubuntu-26.04-cloudinit \
  --memory 2048 --balloon 0 \
  --cores 2 --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single \
  --agent enabled=1 \
  --ostype l26 \
  --serial0 socket --vga serial0 \
  --tags template,ubuntu,2604

qm set $VMID --scsi0 local-lvm:0,import-from=$IMG,discard=on,ssd=1,iothread=1,cache=none
qm set $VMID --ide2 local-lvm:cloudinit
qm set $VMID --boot order=scsi0
qm set $VMID --sshkey /root/.ssh/authorized_keys

qm template $VMID
qm set $VMID --protection 1

# 4. Test
qm clone 9000 999 --name test-clone
qm set 999 --protection 0 --ciuser ericwu --ipconfig0 ip=dhcp
qm start 999
sleep 30
# Get IP and try SSH; cleanup:
qm stop 999 && qm destroy 999 --purge --destroy-unreferenced-disks 1
```

## Quick reference: create a new VM from the template

### 1. Clone, configure, start (on the PVE host)

```bash
TEMPLATE=9000
NEW=113
NAME=db-prod

qm clone $TEMPLATE $NEW --name $NAME
qm resize $NEW scsi0 +97G                                  # ~100G total
qm set $NEW \
  --ciuser ericwu \
  --ipconfig0 ip=dhcp \
  --nameserver 1.1.1.1 \
  --memory 4096 --cores 4
qm start $NEW
```

30 seconds later: `ssh ericwu@<ip>`. You're now on a minimal Ubuntu — just a working SSH, no Docker, no dev tools.

### 2. Install everything you actually want (inside the VM)

Run [`setup-vps.sh`](../setup-vps.sh) from the dotfiles repo. It's interactive and lets you pick which components to install per VM (common tools, security, mosh, zsh + Oh My Zsh, UV, NVM, Docker, Tailscale, Bun, Claude Code, dotfiles, swap, …):

```bash
# Inside the new VM, as your user (with sudo)
curl -fsSL https://raw.githubusercontent.com/tanker327/dotfiles/master/vps/setup-vps.sh | sudo bash
```

Or if you cloned the dotfiles repo already:

```bash
sudo bash ~/dotfiles/vps/setup-vps.sh
```

`setup-vps.sh` is **resumable** — if you ctrl-C halfway through, just re-run and it skips completed steps via `/root/.vps-setup-state`. Logs land in `/root/vps-setup-info.txt`.

After it finishes you'll have a fully-configured server with all selected components, your user account in `sudo` (and `docker` if you chose Docker), dotfiles symlinked, SSH keys generated, and an `~/after_setup_todo.txt` with the next-step checklist (change password, add SSH key to GitHub, etc.).

### 3. (If you want a DB) run setup-postgres.sh

For a Postgres VM, after `setup-vps.sh` finishes:

```bash
sudo bash ~/dotfiles/vps/db/setup-postgres.sh
```

See [`vps/db/`](../db/) for details.
