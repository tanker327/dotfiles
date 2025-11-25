# SSH Keys Directory

This directory contains SSH public keys that will be automatically installed on new VPS setups.

## Files

### authorized_keys
Contains public SSH keys that will be added to `~/.ssh/authorized_keys` for the new user account during VPS setup.

**IMPORTANT SECURITY NOTES:**
- ✅ Only store **PUBLIC** keys (*.pub) in this directory
- ❌ **NEVER** commit private keys to this repository
- ✅ Safe to commit to git and share publicly
- 🔒 These keys will allow SSH access to your VPS

## Usage

When you run the VPS setup script (`vps/setup-vps.sh`), it will automatically:
1. Clone this dotfiles repository to the new user's home directory
2. Copy `vps/ssh-keys/authorized_keys` to `~/.ssh/authorized_keys`
3. Set proper permissions (600 for file, 700 for .ssh directory)

## Adding More Keys

To add additional SSH keys for access:

1. Append the public key to the `authorized_keys` file:
   ```bash
   echo "ssh-rsa AAAA... user@host" >> authorized_keys
   ```

2. Commit and push the changes:
   ```bash
   git add vps/ssh-keys/authorized_keys
   git commit -m "Add new SSH key for <purpose>"
   git push
   ```

## Manual Installation

If you need to manually add keys to an existing server:

```bash
# On your VPS
cat ~/dotfiles/vps/ssh-keys/authorized_keys >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

## Current Keys

- `tanker327@gmail.com` - Main access key
