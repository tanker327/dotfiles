# My Dot Files

Personal dotfiles repository for macOS and Ubuntu/VPS system configuration. Contains shell configuration, git configuration, custom scripts, and installation automation.

## Quick Start

### macOS Setup

```bash
# Clone the repository
git clone https://github.com/tanker327/dotfiles.git ~/dotfiles
cd ~/dotfiles

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

**One-line setup (recommended):**
```bash
curl -fsSL https://raw.githubusercontent.com/tanker327/dotfiles/master/vps/setup-vps.sh | sudo bash
```

**Or manual setup:**
```bash
# Clone the repository
git clone https://github.com/tanker327/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Basic Ubuntu initialization
./ubuntu-init.sh

# Interactive VPS setup with component selection
sudo bash vps/setup-vps.sh
```

The VPS setup script is interactive and allows selecting:
- Basic tools, security (UFW/fail2ban), Zsh, UV (Python), NVM (Node.js)
- Docker, Tailscale, Claude Code, swap setup, user creation
- Automatic dotfiles configuration

**Note:** The script sets the initial user password to the username. You MUST change it immediately after first login.

## Repository Structure

```
dotfiles/
├── zsh/
│   ├── zshrc          # Main zsh configuration
│   └── dev            # Docker, tmux, Claude Code aliases
├── git/
│   ├── gitconfig      # Git configuration
│   ├── gitignore_global
│   └── new-git-command/  # Custom git commands
├── vim/               # Vim configuration
├── vps/
│   ├── setup-vps.sh   # VPS setup script
│   └── ssh-keys/      # SSH authorized keys
├── install.sh         # macOS dotfiles installer
├── brew.sh            # Homebrew packages
├── brew-cask.sh       # Homebrew cask applications
└── ubuntu-init.sh     # Ubuntu initialization
```

## Key Features

### Shell Configuration (zsh/zshrc)
- Oh-my-zsh integration
- Custom aliases and functions
- Docker compose shortcuts: `dc`, `dcr`, `dcupdate`, `up`, `down`, `dlog`
- Claude Code alias: `cc` (for `claude --dangerously-skip-permissions`)
- Environment variable loading from `~/.env-keyexport`

### Git Configuration
- Diff-so-fancy integration
- Useful aliases: `st`, `co`, `cm`, `br`, `lg`, `pushf`
- Custom git commands in PATH
- Global gitignore

### Custom Git Commands
Located in `git/new-git-command/`:
- `admin-release`, `git-new`, `git-pullme`, `git-pushme`, `git-save`, `newsql`

### Important Paths
- Custom git commands: `$HOME/dotfiles/git/new-git-command`
- Local binaries: `$HOME/.local/bin`
- NVM: `$HOME/.nvm`
- Antigravity: `$HOME/.antigravity/antigravity/bin` (conditionally added)

## VPS Setup Details

The `vps/setup-vps.sh` script provides:
- **Resume capability**: Can resume interrupted installations
- **Component selection**: Choose what to install
- **Automatic configuration**: Dotfiles, SSH keys, user setup
- **Security hardening**: UFW firewall, fail2ban
- **Development tools**: Python (UV), Node.js (NVM), Docker, Claude Code

Components available:
- Common tools (curl, wget, git, vim, htop, unzip, tree, build-essential)
- Security (UFW firewall + fail2ban)
- Zsh + Oh My Zsh
- UV (Python 3.12 package manager)
- NVM (Node.js 22)
- Docker + Docker Compose
- Tailscale VPN
- Claude Code CLI
- Swap space configuration
- Dotfiles installation

## Important Notes

- **Docker commands**: Always use `docker compose` (not `docker-compose`)
- **Backups**: Install scripts backup existing configs to `$HOME/.backup`
- **SSH keys**: Setup script includes SSH key management
- **Security**: Initial password is set to username - change immediately!

## Post-Installation

After running the VPS setup script:

1. **Change your password immediately**:
   ```bash
   passwd
   ```

2. **Generate SSH keys** (for GitHub/GitLab):
   ```bash
   ssh-keygen -t ed25519 -C "your@email.com"
   cat ~/.ssh/id_ed25519.pub
   ```

3. **Connect to Tailscale** (if installed):
   ```bash
   sudo tailscale up
   ```

4. **Authenticate Claude Code** (if installed):
   ```bash
   claude auth
   ```

5. **Consider SSH hardening**:
   - Change SSH port from 22
   - Set `PermitRootLogin no`
   - Set `PasswordAuthentication no` (after setting up SSH keys)

## License

Personal dotfiles - use at your own risk.
