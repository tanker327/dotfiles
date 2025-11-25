# VPS Setup Script - Resume Capability

The VPS setup script (`setup-vps.sh`) now supports automatic resume functionality. If the installation fails at any point, you can simply re-run the script and it will continue from where it left off.

## How It Works

### State Tracking
- The script saves its configuration to `/root/.vps-setup-state`
- Each installation step is marked as complete when it finishes successfully
- If the script fails mid-installation, the state file preserves your progress

### Resume Behavior

When you re-run the script after a failure:

1. **Detection**: The script detects the previous installation state file
2. **Confirmation**: You'll be asked: `Resume previous installation? (y/n)`
3. **Resume**: If you choose `y`, the script:
   - Loads your previous configuration (username, selections, etc.)
   - Skips all completed steps
   - Continues from the first uncompleted step

## Usage Examples

### First Run (Fails at Docker Installation)
```bash
curl -fsSL https://raw.githubusercontent.com/tanker327/dotfiles/master/vps/setup-vps.sh | sudo bash
# Script runs but fails during Docker installation
```

### Resume After Failure
```bash
# Simply re-run the same command
curl -fsSL https://raw.githubusercontent.com/tanker327/dotfiles/master/vps/setup-vps.sh | sudo bash

# You'll see:
# Previous installation detected!
# Resume previous installation? (y/n): y
# [INFO] Resuming previous installation...
# [INFO] Step 'update_system' already completed, skipping...
# [INFO] Step 'check_ssh_keys' already completed, skipping...
# [INFO] Step 'create_user' already completed, skipping...
# ... continues from where it failed
```

### Start Fresh (Ignore Previous State)
```bash
curl -fsSL https://raw.githubusercontent.com/tanker327/dotfiles/master/vps/setup-vps.sh | sudo bash

# When prompted:
# Resume previous installation? (y/n): n
# [WARNING] Starting fresh installation...
# ... starts from the beginning
```

## State File Location

- **Location**: `/root/.vps-setup-state`
- **Contents**:
  - Your configuration choices (username, git config, component selections)
  - Completion status of each installation step
- **Cleanup**: Automatically deleted when installation completes successfully

## Tracked Steps

Each of these steps is independently tracked:

1. `update_system` - System update and upgrade
2. `check_ssh_keys` - SSH key generation
3. `install_common_tools` - Common development tools
4. `install_security` - UFW and fail2ban
5. `install_zsh` - Zsh and Oh My Zsh
6. `install_uv_python` - UV and Python 3.12
7. `install_nvm_node` - NVM and Node.js 22
8. `install_docker` - Docker and Docker Compose
9. `install_tailscale` - Tailscale VPN
10. `install_claude_code` - Claude Code CLI
11. `setup_swap_space` - Swap configuration
12. `create_user` - User account creation
13. `install_dotfiles` - Dotfiles configuration

## Manual State Management

### View Current State
```bash
cat /root/.vps-setup-state
```

### Clear State (Start Fresh)
```bash
rm -f /root/.vps-setup-state
```

### Check What's Completed
```bash
grep "=done" /root/.vps-setup-state
```

## Benefits

1. **Resilient**: Network failures or timeouts won't force you to restart
2. **Time-Saving**: Skips already-completed steps
3. **Idempotent**: Safe to run multiple times
4. **Transparent**: Shows exactly what's being skipped

## Notes

- Each installation function checks if it's already complete before running
- Functions are designed to be idempotent (safe to run multiple times)
- The state file is only deleted after successful completion
- You can manually delete the state file to force a fresh installation
