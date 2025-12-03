# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository for macOS and Ubuntu/VPS system configuration. It contains shell configuration, git configuration, custom scripts, and installation automation.

## Key Configuration Files

### Shell Configuration
- **zsh/zshrc**: Main zsh configuration (symlinked to ~/.zshrc)
- **zsh/dev**: Contains Docker, tmux, and Claude Code aliases
  - Uses `docker compose` (not docker-compose)
  - Defines `cc` alias for `claude --dangerously-skip-permissions`
  - Docker compose command shortcuts: `dc`, `dcr`, `dcupdate`, `up`, `down`, `dlog`

### Git Configuration
- **git/gitconfig**: Main git config with aliases and diff-so-fancy integration
- **git/gitignore_global**: Global gitignore file
- **git/new-git-command/**: Custom git commands added to PATH
  - Custom commands: admin-release, git-new, git-pullme, git-pushme, git-save, newsql

### Important Paths
- Custom git commands: `$HOME/dotfiles/git/new-git-command` (in PATH)
- Local binaries: `$HOME/.local/bin` (in PATH)
- NVM: `$HOME/.nvm`
- Antigravity: `$HOME/.antigravity/antigravity/bin` (conditionally added to PATH)

## Installation Commands

### macOS Setup
```bash
# Full dotfiles installation (symlinks zshrc, gitconfig, etc.)
./install.sh

# Install Homebrew packages
./brew.sh

# Install cask applications
./brew-cask.sh

# Install other dependencies (Ruby gems)
./install-other.sh
```

### Ubuntu/VPS Setup
```bash
# One-line remote VPS setup (recommended)
curl -fsSL https://raw.githubusercontent.com/tanker327/dotfiles/master/vps/setup-vps.sh | sudo bash

# Or basic Ubuntu initialization
./ubuntu-init.sh

# Or interactive VPS setup with component selection
sudo bash vps/setup-vps.sh
```

The VPS setup script (`vps/setup-vps.sh`) is interactive and allows selecting:
- Basic tools, security (UFW/fail2ban), Zsh, UV (Python), NVM (Node.js)
- Docker, Tailscale, Claude Code, swap setup, user creation, SSH keys
- **Resume capability**: Can resume interrupted installations using state file at `/root/.vps-setup-state`
- **Password policy**: Sets initial password to username (MUST be changed after login)

## Key Git Aliases
- `st` = status
- `co` = checkout
- `cm` = commit
- `br` = branch
- `una`/`unadd` = reset HEAD
- `uncm`/`uncommit` = reset --soft HEAD^
- `lg` = formatted log with graph
- `pushf`/`fpush` = force push to origin
- `cp` = cherry-pick

## Architecture

The repository follows a modular structure:
- Installation scripts are at the root level
- Configuration files organized by tool (zsh/, git/, vim/, etc.)
- Backup strategy: moves existing configs to `$HOME/.backup` before symlinking
- Shell scripts use symlinks to maintain single source of truth

## Environment Variables
- Environment keys loaded from `~/.env-keyexport` if present (zsh/zshrc:67)
- JAVA_HOME auto-detected via `/usr/libexec/java_home` on macOS
- Docker completions configured for zsh

## VPS Setup Script Architecture

### State Management (vps/setup-vps.sh)
- **State file**: `/root/.vps-setup-state` stores configuration and tracks completed steps
- **Log file**: `/root/vps-setup-info.txt` contains installation details and credentials
- **Resume logic**: Script detects previous runs and offers to resume from last successful step
- **Step tracking**: Each installation function uses `skip_if_complete()` and `mark_step_complete()`

### Security Features
- Initial user password set to username (must be changed immediately)
- SSH keys automatically installed from `vps/ssh-keys/authorized_keys` if present
- UFW firewall preconfigured with ports 22, 80, 443
- fail2ban installed and enabled for brute-force protection

### Installation Flow (Root vs User Separation)

**Important Architecture Principle**: The script separates system-level setup (must run as root) from user development environment (runs as new user). **Root never has development tools installed.**

#### Phase 1-2: Initialization (as root)
1. **collect_user_inputs()**: Gather all configuration upfront (or resume from state file)
2. **update_system()**: Update package lists and upgrade system
3. **check_ssh_keys()**: Generate ED25519 SSH key for root if needed for system use

#### Phase 3: User Creation (as root)
4. **create_user()**: Create user with temporary password (username), add to sudo/docker groups

#### Phase 4: System Packages & Services (as root)
5. **install_common_tools()**: Install system packages (curl, git, vim, build-essential, etc.)
6. **install_security()**: Configure UFW firewall and fail2ban
7. **install_zsh()**: Install zsh package system-wide (NOT configured for root)
8. **install_docker()**: Install Docker daemon and compose plugin
9. **install_tailscale()**: Install Tailscale VPN client
10. **setup_swap_space()**: Configure swap file

#### Phase 5: User Development Environment (as new user via `su`)
11. **install_user_environment()**: Comprehensive user setup including:
    - Clone dotfiles repository
    - Configure Git (user.name, user.email)
    - Symlink dotfiles (.zshrc, .gitconfig, .gitignore_global)
    - Install SSH authorized_keys from dotfiles
    - Install Oh My Zsh + plugins (zsh-autosuggestions, zsh-syntax-highlighting)
    - Install NVM + Node.js 22
    - Install UV + Python 3.12
    - Install Claude Code CLI
    - Change user's default shell to zsh

#### Phase 6: Finalization
12. **show_summary()**: Display next steps, create `~/after_setup_todo.txt`, cleanup state file

## SSH Keys Management
- **Location**: `vps/ssh-keys/authorized_keys` contains public keys for VPS access
- **Auto-installation**: VPS setup script copies to `~/.ssh/authorized_keys` with proper permissions (600)
- **IMPORTANT**: Only commit PUBLIC keys (*.pub), never private keys
- Root SSH key generated at `/root/.ssh/id_ed25519` during VPS setup
- Each user should generate their own SSH keys after account creation

## Zsh Plugin Management
The install.sh script automatically installs:
- **zsh-autosuggestions**: Fish-like autosuggestions
- **zsh-syntax-highlighting**: Syntax highlighting for commands

Plugins are cloned to `$ZSH_CUSTOM/plugins/` (default: `~/.oh-my-zsh/custom/plugins/`)

## Important Notes
- Always use `docker compose` (not docker-compose) per zsh/dev configuration
- Oh-my-zsh is a prerequisite for zsh configuration
- The install.sh script backs up existing configs to `$HOME/.backup` with timestamps
- Custom welcome banner displayed on shell startup showing hostname
- VPS setup state file should be cleaned up automatically on successful completion
