#!/bin/bash

VERSION="2.4.0"

# Pinned versions for reproducibility — bump as needed
NVM_VERSION="v0.40.1"
NODE_VERSION="22"
PYTHON_VERSION="3.12"

# Dotfiles repo URL — override to test the local working tree
DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-https://github.com/tanker327/dotfiles.git}"

#####################################################
# VPS Setup Script - Complete Server Configuration
#####################################################
# Supports: Ubuntu and Debian
# Usage: curl -fsSL <your-url>/setup-vps.sh | sudo bash
# Or: sudo bash setup-vps.sh
#####################################################

set -e
set -o pipefail

# Wire fd 3 (read) and fd 4 (prompt) directly to /dev/tty when possible.
# Under `curl | sudo bash` the script body is on stdin and stderr can be
# intercepted by sudoers log_output / wrapper scripts — writing the prompt
# to /dev/tty bypasses both. Fall back to stdin/stderr when no controlling
# terminal exists (Docker -i, CI).
if ! exec 3< /dev/tty 2>/dev/null; then
    exec 3<&0
fi
if ! exec 4> /dev/tty 2>/dev/null; then
    exec 4>&2
fi

# `read -p PROMPT VAR <&3` looks correct but bash decides whether to print
# PROMPT based on its own tty heuristic against the redirected fd, which
# silently drops the prompt on some terminals/sudo configurations even when
# fd 3 *is* /dev/tty. Print prompts ourselves and read separately.
ask() {
    local __prompt="$1"
    local __var="$2"
    printf "%s" "$__prompt" >&4
    read "$__var" <&3
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log and state files
SETUP_INFO_FILE="/root/vps-setup-info.txt"
STATE_FILE="/root/.vps-setup-state"

#####################################################
# Utility Functions
#####################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$SETUP_INFO_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$SETUP_INFO_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$SETUP_INFO_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$SETUP_INFO_FILE"
}

section_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# State management functions
mark_step_complete() {
    echo "$1=done" >> "$STATE_FILE"
    log_info "Step '$1' marked as complete"
}

is_step_complete() {
    [ -f "$STATE_FILE" ] && grep -q "^$1=done$" "$STATE_FILE"
}

skip_if_complete() {
    local step_name="$1"
    if is_step_complete "$step_name"; then
        log_info "Step '$step_name' already completed, skipping..."
        return 0
    fi
    return 1
}

#####################################################
# Pre-flight Checks
#####################################################

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

#####################################################
# Input Collection Phase
#####################################################

validate_existing_user() {
    local username="$1"

    # Check if user exists
    if ! id "$username" &>/dev/null; then
        log_error "User '$username' does not exist on this system"
        log_error "Please create the user first or choose to create a new user"
        exit 1
    fi

    # Check if user is in sudo group
    if ! groups "$username" | grep -q '\bsudo\b'; then
        log_error "User '$username' is not in the sudo group"
        log_error "Please add user to sudo group first: usermod -aG sudo $username"
        exit 1
    fi

    log_success "User '$username' validated (exists and has sudo privileges)"
}

collect_user_inputs() {
    section_header "VPS Setup Configuration (Version $VERSION)"

    echo -e "${GREEN}Welcome to the VPS Setup Script!${NC}"
    echo "This script will configure your server with selected components."
    echo ""

    # Check if resuming from previous run
    if [ -f "$STATE_FILE" ]; then
        echo -e "${YELLOW}Previous installation detected!${NC}"
        echo ""
        ask "Resume previous installation? (y/n): " RESUME_INSTALL
        if [ "$RESUME_INSTALL" = "y" ]; then
            log_info "Resuming previous installation..."
            # Load previous configuration
            source "$STATE_FILE"
            return 0
        else
            log_warning "Starting fresh installation..."
            rm -f "$STATE_FILE"
        fi
    fi

    echo "All configuration will be collected upfront, then installation"
    echo "will proceed without interruption."
    echo ""

    # Initialize setup info file
    echo "VPS Setup - $(date)" > "$SETUP_INFO_FILE"
    echo "========================================" >> "$SETUP_INFO_FILE"
    echo "" >> "$SETUP_INFO_FILE"

    # Ask if user wants to create new user or use existing
    echo ""
    ask "Use existing user instead of creating new one? (y/n) [N]: " USE_EXISTING_USER
    USE_EXISTING_USER=${USE_EXISTING_USER:-n}

    if [ "$USE_EXISTING_USER" = "y" ]; then
        CREATE_NEW_USER="n"

        # Auto-detect from SUDO_USER
        if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
            log_error "Cannot detect non-root user from environment"
            log_error "This script must be run with 'sudo' by a non-root user"
            log_error "Example: sudo bash setup-vps.sh"
            log_error ""
            log_error "Installing development environment for root is not supported for security reasons"
            exit 1
        fi

        NEW_USERNAME="$SUDO_USER"
        log_info "Detected user: $NEW_USERNAME"

        # Validate the existing user
        validate_existing_user "$NEW_USERNAME"
    else
        CREATE_NEW_USER="y"

        # Collect new username
        while true; do
            ask "Enter username for new user account: " NEW_USERNAME
            if [ -z "$NEW_USERNAME" ]; then
                log_warning "Username cannot be empty"
                continue
            fi
            if id "$NEW_USERNAME" &>/dev/null; then
                log_warning "User $NEW_USERNAME already exists"
                ask "Continue with existing user? (y/n): " confirm
                if [ "$confirm" = "y" ]; then
                    break
                fi
            else
                break
            fi
        done
    fi

    # Collect git configuration
    ask "Enter Git user name [tanker]: " GIT_USER_NAME
    GIT_USER_NAME=${GIT_USER_NAME:-tanker}
    ask "Enter Git email [tanker327@gmail.com]: " GIT_USER_EMAIL
    GIT_USER_EMAIL=${GIT_USER_EMAIL:-tanker327@gmail.com}

    # Component selection
    echo ""
    echo -e "${YELLOW}Select components to install (y/n for each):${NC}"
    echo ""

    ask "Install common tools (curl, wget, git, vim, htop, unzip, tree, build-essential)? [Y/n]: " INSTALL_TOOLS
    INSTALL_TOOLS=${INSTALL_TOOLS:-y}

    ask "Install security tools (UFW firewall + fail2ban)? [Y/n]: " INSTALL_SECURITY
    INSTALL_SECURITY=${INSTALL_SECURITY:-y}

    ask "Install Mosh (keeps SSH sessions alive on flaky networks)? [Y/n]: " INSTALL_MOSH
    INSTALL_MOSH=${INSTALL_MOSH:-y}

    ask "Install Zsh + Oh My Zsh? [Y/n]: " INSTALL_ZSH
    INSTALL_ZSH=${INSTALL_ZSH:-y}

    ask "Install UV (Python package manager) with Python ${PYTHON_VERSION}? [Y/n]: " INSTALL_UV
    INSTALL_UV=${INSTALL_UV:-y}

    ask "Install NVM with Node.js ${NODE_VERSION}? [Y/n]: " INSTALL_NVM
    INSTALL_NVM=${INSTALL_NVM:-y}

    ask "Install Docker + Docker Compose? [Y/n]: " INSTALL_DOCKER
    INSTALL_DOCKER=${INSTALL_DOCKER:-y}

    ask "Install Tailscale VPN? [Y/n]: " INSTALL_TAILSCALE
    INSTALL_TAILSCALE=${INSTALL_TAILSCALE:-y}

    ask "Install Bun (JavaScript runtime)? [Y/n]: " INSTALL_BUN
    INSTALL_BUN=${INSTALL_BUN:-y}

    ask "Install Claude Code CLI? [Y/n]: " INSTALL_CLAUDE
    INSTALL_CLAUDE=${INSTALL_CLAUDE:-y}

    ask "Install OpenAI Codex CLI (requires NVM)? [Y/n]: " INSTALL_CODEX
    INSTALL_CODEX=${INSTALL_CODEX:-y}

    ask "Configure swap space (recommended for low-memory VPS)? [Y/n]: " SETUP_SWAP
    SETUP_SWAP=${SETUP_SWAP:-y}

    # Password configuration - will use username as initial password
    log_info "Initial password will be set to username (must be changed after login)"

    if [ "$SETUP_SWAP" = "y" ]; then
        # Calculate recommended swap size based on RAM
        TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))

        # Swap size recommendation logic:
        # RAM <= 2GB: swap = 2x RAM
        # 2GB < RAM <= 8GB: swap = RAM
        # RAM > 8GB: swap = 4GB
        if [ $TOTAL_RAM_GB -le 2 ]; then
            RECOMMENDED_SWAP=$((TOTAL_RAM_GB * 2))
            [ $RECOMMENDED_SWAP -lt 1 ] && RECOMMENDED_SWAP=2
        elif [ $TOTAL_RAM_GB -le 8 ]; then
            RECOMMENDED_SWAP=$TOTAL_RAM_GB
        else
            RECOMMENDED_SWAP=4
        fi

        echo "Detected RAM: ${TOTAL_RAM_GB}GB"
        ask "Swap size in GB [recommended: ${RECOMMENDED_SWAP}]: " SWAP_SIZE
        SWAP_SIZE=${SWAP_SIZE:-$RECOMMENDED_SWAP}
    fi

    ask "Clone and apply dotfiles from github.com/tanker327? [Y/n]: " INSTALL_DOTFILES
    INSTALL_DOTFILES=${INSTALL_DOTFILES:-y}

    ask "Generate ed25519 SSH key for user (id_ed25519 for GitHub/GitLab)? [Y/n]: " GENERATE_SSH_KEY
    GENERATE_SSH_KEY=${GENERATE_SSH_KEY:-y}

    # Summary of selections
    echo ""
    section_header "Configuration Summary"
    echo -e "${GREEN}Username:${NC} $NEW_USERNAME"
    echo -e "${GREEN}Git Config:${NC} $GIT_USER_NAME <$GIT_USER_EMAIL>"
    echo ""
    echo "Components to install:"
    [ "$INSTALL_TOOLS" = "y" ] && echo "   Common tools"
    [ "$INSTALL_SECURITY" = "y" ] && echo "   Security (UFW + fail2ban)"
    [ "$INSTALL_MOSH" = "y" ] && echo "   Mosh"
    [ "$INSTALL_ZSH" = "y" ] && echo "   Zsh + Oh My Zsh"
    [ "$INSTALL_UV" = "y" ] && echo "   UV (Python ${PYTHON_VERSION})"
    [ "$INSTALL_NVM" = "y" ] && echo "   NVM (Node.js ${NODE_VERSION})"
    [ "$INSTALL_DOCKER" = "y" ] && echo "   Docker + Docker Compose"
    [ "$INSTALL_TAILSCALE" = "y" ] && echo "   Tailscale VPN"
    [ "$INSTALL_CLAUDE" = "y" ] && echo "   Claude Code"
    [ "$INSTALL_CODEX" = "y" ] && echo "   OpenAI Codex"
    [ "$INSTALL_BUN" = "y" ] && echo "   Bun"
    [ "$SETUP_SWAP" = "y" ] && echo "   Swap space (${SWAP_SIZE}GB)"
    [ "$INSTALL_DOTFILES" = "y" ] && echo "   Dotfiles configuration"
    [ "$GENERATE_SSH_KEY" = "y" ] && echo "   ed25519 SSH key for user"
    echo ""

    ask "Proceed with installation? [Y/n]: " CONFIRM_INSTALL
    CONFIRM_INSTALL=${CONFIRM_INSTALL:-y}
    if [ "$CONFIRM_INSTALL" != "y" ]; then
        log_warning "Installation cancelled by user"
        exit 0
    fi

    # Save configuration to state file
    cat > "$STATE_FILE" <<EOF
# VPS Setup Configuration - $(date)
NEW_USERNAME="$NEW_USERNAME"
CREATE_NEW_USER="$CREATE_NEW_USER"
GIT_USER_NAME="$GIT_USER_NAME"
GIT_USER_EMAIL="$GIT_USER_EMAIL"
INSTALL_TOOLS="$INSTALL_TOOLS"
INSTALL_SECURITY="$INSTALL_SECURITY"
INSTALL_MOSH="$INSTALL_MOSH"
INSTALL_ZSH="$INSTALL_ZSH"
INSTALL_UV="$INSTALL_UV"
INSTALL_NVM="$INSTALL_NVM"
INSTALL_DOCKER="$INSTALL_DOCKER"
INSTALL_TAILSCALE="$INSTALL_TAILSCALE"
INSTALL_BUN="$INSTALL_BUN"
INSTALL_CLAUDE="$INSTALL_CLAUDE"
INSTALL_CODEX="$INSTALL_CODEX"
SETUP_SWAP="$SETUP_SWAP"
SWAP_SIZE="$SWAP_SIZE"
INSTALL_DOTFILES="$INSTALL_DOTFILES"
GENERATE_SSH_KEY="$GENERATE_SSH_KEY"
EOF
    log_success "Configuration saved to $STATE_FILE"
}

#####################################################
# Installation Functions
#####################################################

update_system() {
    skip_if_complete "update_system" && return 0

    section_header "System Update"
    log_info "Updating package lists and upgrading system..."
    apt update -y
    apt upgrade -y
    log_success "System updated successfully"

    mark_step_complete "update_system"
}

check_ssh_keys() {
    skip_if_complete "check_ssh_keys" && return 0

    section_header "SSH Key Check"
    if [ ! -f /root/.ssh/id_ed25519 ]; then
        log_info "Generating SSH key (ED25519)..."
        mkdir -p /root/.ssh
        ssh-keygen -t ed25519 -C "$GIT_USER_EMAIL" -f /root/.ssh/id_ed25519 -N ""
        log_success "SSH key generated at /root/.ssh/id_ed25519"
        echo "" >> "$SETUP_INFO_FILE"
        echo "SSH Public Key:" >> "$SETUP_INFO_FILE"
        cat /root/.ssh/id_ed25519.pub >> "$SETUP_INFO_FILE"
        echo "" >> "$SETUP_INFO_FILE"
    else
        log_info "SSH key already exists"
    fi

    mark_step_complete "check_ssh_keys"
}

install_common_tools() {
    skip_if_complete "install_common_tools" && return 0

    section_header "Installing Common Tools"
    log_info "Installing curl, wget, git, vim, htop, btop, unzip, tree, tmux, build-essential..."
    apt install -y curl wget git vim htop btop unzip tree build-essential \
        net-tools locate openssh-server openssh-client \
        tmux command-not-found
    log_success "Common tools installed"

    mark_step_complete "install_common_tools"
}

install_security() {
    skip_if_complete "install_security" && return 0

    section_header "Installing Security Tools"

    log_info "Installing UFW firewall..."
    apt install -y ufw

    # Configure UFW
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    echo "y" | ufw enable
    log_success "UFW firewall configured (ports 22, 80, 443 allowed)"

    log_info "Installing fail2ban..."
    apt install -y fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
    log_success "fail2ban installed and enabled"

    mark_step_complete "install_security"
}

install_mosh() {
    skip_if_complete "install_mosh" && return 0

    section_header "Installing Mosh"

    log_info "Installing mosh..."
    apt install -y mosh
    log_success "Mosh installed"

    # Mosh uses UDP 60000-61000. Open them if UFW is active.
    if command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        log_info "Opening UFW ports 60000:61000/udp for mosh..."
        ufw allow 60000:61000/udp
        log_success "UFW configured for mosh"
    else
        log_info "UFW not active; if you enable a firewall later, allow 60000:61000/udp for mosh"
    fi

    mark_step_complete "install_mosh"
}

install_zsh() {
    skip_if_complete "install_zsh" && return 0

    section_header "Installing Zsh (System Package)"

    log_info "Installing Zsh package..."
    apt install -y zsh
    log_success "Zsh installed (will be configured for user later)"

    mark_step_complete "install_zsh"
}

# UV and NVM installation removed - will be installed for user in install_user_environment()

install_docker() {
    skip_if_complete "install_docker" && return 0

    section_header "Installing Docker + Docker Compose"

    # Detect OS (Ubuntu or Debian)
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
    else
        log_error "Cannot detect OS type"
        return 1
    fi

    log_info "Detected OS: $OS_ID"

    # Validate supported OS
    if [ "$OS_ID" != "ubuntu" ] && [ "$OS_ID" != "debian" ]; then
        log_error "Unsupported OS: $OS_ID (only Ubuntu and Debian are supported)"
        return 1
    fi

    log_info "Installing Docker prerequisites..."
    apt install -y apt-transport-https ca-certificates gnupg lsb-release

    log_info "Adding Docker GPG key and repository for $OS_ID..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt update -y

    log_info "Installing Docker Engine and Docker Compose..."
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    # Add user to docker group
    usermod -aG docker "$NEW_USERNAME" || log_warning "User $NEW_USERNAME not yet created, will add to docker group later"

    log_success "Docker and Docker Compose installed"
    docker --version >> "$SETUP_INFO_FILE"
    docker compose version >> "$SETUP_INFO_FILE"

    mark_step_complete "install_docker"
}

install_tailscale() {
    skip_if_complete "install_tailscale" && return 0

    section_header "Installing Tailscale VPN"

    log_info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh

    log_success "Tailscale installed"
    log_info "Run 'sudo tailscale up' to connect to your Tailscale network"

    mark_step_complete "install_tailscale"
}

# Claude Code installation removed - will be installed for user in install_user_environment()

setup_swap_space() {
    skip_if_complete "setup_swap_space" && return 0

    section_header "Setting Up Swap Space"

    # Skip cleanly if swap already active
    if swapon --show 2>/dev/null | grep -q '/swapfile'; then
        log_info "Swap file /swapfile already active, skipping creation"
        if ! grep -q '/swapfile' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
            log_info "Added /swapfile to /etc/fstab"
        fi
        free -h >> "$SETUP_INFO_FILE"
        mark_step_complete "setup_swap_space"
        return 0
    fi

    # If /swapfile exists but is inactive, remove it before recreating
    if [ -f /swapfile ]; then
        log_warning "Found stale /swapfile, removing before recreate"
        rm -f /swapfile
    fi

    log_info "Creating ${SWAP_SIZE}GB swap file..."
    fallocate -l ${SWAP_SIZE}G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    # Make swap permanent
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    log_success "Swap space configured (${SWAP_SIZE}GB)"
    free -h >> "$SETUP_INFO_FILE"

    mark_step_complete "setup_swap_space"
}

create_user() {
    skip_if_complete "create_user" && return 0

    section_header "Creating User Account"

    # Skip user creation if using existing user
    if [ "$CREATE_NEW_USER" = "n" ]; then
        log_info "Skipping user creation (using existing user: $NEW_USERNAME)"

        echo "" >> "$SETUP_INFO_FILE"
        echo "=== USER ACCOUNT INFO ===" >> "$SETUP_INFO_FILE"
        echo "Username: $NEW_USERNAME (existing user, password unchanged)" >> "$SETUP_INFO_FILE"
        echo "=========================" >> "$SETUP_INFO_FILE"
        echo "" >> "$SETUP_INFO_FILE"

        # Add to docker group if docker is installed and user not already in group
        if command -v docker &> /dev/null; then
            if ! groups "$NEW_USERNAME" | grep -q '\bdocker\b'; then
                usermod -aG docker "$NEW_USERNAME"
                log_info "Added $NEW_USERNAME to docker group"
            else
                log_info "User $NEW_USERNAME already in docker group"
            fi
        fi

        mark_step_complete "create_user"
        return 0
    fi

    # Original user creation logic for new users
    if id "$NEW_USERNAME" &>/dev/null; then
        log_info "User $NEW_USERNAME already exists, skipping creation"
    else
        log_info "Creating user $NEW_USERNAME..."
        adduser --gecos "" --disabled-password "$NEW_USERNAME"

        # Set password to username (temporary)
        echo "$NEW_USERNAME:$NEW_USERNAME" | chpasswd
        log_success "Temporary password set to username (must be changed after login)"

        echo "" >> "$SETUP_INFO_FILE"
        echo "=== USER ACCOUNT INFO ===" >> "$SETUP_INFO_FILE"
        echo "Username: $NEW_USERNAME" >> "$SETUP_INFO_FILE"
        echo "Initial Password: $NEW_USERNAME (MUST CHANGE AFTER FIRST LOGIN)" >> "$SETUP_INFO_FILE"
        echo "=========================" >> "$SETUP_INFO_FILE"
        echo "" >> "$SETUP_INFO_FILE"

        # Add to sudo group
        usermod -aG sudo "$NEW_USERNAME"

        log_success "User $NEW_USERNAME created and added to sudo group"
    fi

    # Add to docker group if docker is installed
    if command -v docker &> /dev/null; then
        usermod -aG docker "$NEW_USERNAME"
        log_info "Added $NEW_USERNAME to docker group"
    fi

    mark_step_complete "create_user"
}

#####################################################
# User Environment Sub-Steps
# Each is independently tracked so a mid-run failure resumes cleanly.
# All sub-steps assume USER_HOME, DOTFILES_DIR, BACKUP_DIR are set
# (populated by _user_env_init_paths).
#####################################################

_user_env_init_paths() {
    # Idempotent: just sets globals. Safe to call from every sub-step.
    USER_HOME=$(getent passwd "$NEW_USERNAME" | cut -d: -f6)
    if [ -z "$USER_HOME" ]; then
        log_error "Could not determine home directory for user $NEW_USERNAME"
        return 1
    fi
    DOTFILES_DIR="$USER_HOME/dotfiles"
    BACKUP_DIR="$USER_HOME/.backup"
}

user_env_clone_dotfiles() {
    skip_if_complete "user_env_clone_dotfiles" && return 0
    _user_env_init_paths || return 1

    section_header "User Env: Clone dotfiles + git config"

    # Ensure git is installed (required for cloning dotfiles)
    if ! command -v git &> /dev/null; then
        log_warning "Git not found, installing git as prerequisite..."
        apt install -y git
        log_success "Git installed"
    fi

    log_info "Cloning dotfiles repository..."
    if [ -d "$DOTFILES_DIR/.git" ]; then
        log_info "Dotfiles repo already present, pulling latest (preserves local changes)..."
        su - "$NEW_USERNAME" -c "cd $DOTFILES_DIR && git pull --ff-only" 2>&1 | tee -a "$SETUP_INFO_FILE" \
            || log_warning "git pull failed (likely local changes) — leaving existing dotfiles in place"
    elif [ -d "$DOTFILES_DIR" ]; then
        log_warning "Dotfiles directory exists but is not a git repo, backing up to ${DOTFILES_DIR}.bak.$(date +%s)"
        mv "$DOTFILES_DIR" "${DOTFILES_DIR}.bak.$(date +%s)"
        su - "$NEW_USERNAME" -c "git clone $DOTFILES_REPO_URL $DOTFILES_DIR" 2>&1 | tee -a "$SETUP_INFO_FILE" \
            || { log_error "Failed to clone dotfiles repository"; return 1; }
    else
        if ! su - "$NEW_USERNAME" -c "git clone $DOTFILES_REPO_URL $DOTFILES_DIR" 2>&1 | tee -a "$SETUP_INFO_FILE"; then
            log_error "Failed to clone dotfiles repository"
            return 1
        fi
    fi

    if [ ! -d "$DOTFILES_DIR" ]; then
        log_error "Dotfiles directory not found after cloning"
        return 1
    fi

    log_info "Configuring Git..."
    su - "$NEW_USERNAME" -c "git config --global user.name '$GIT_USER_NAME'"
    su - "$NEW_USERNAME" -c "git config --global user.email '$GIT_USER_EMAIL'"

    su - "$NEW_USERNAME" -c "mkdir -p $BACKUP_DIR"

    mark_step_complete "user_env_clone_dotfiles"
}

user_env_symlinks() {
    skip_if_complete "user_env_symlinks" && return 0
    _user_env_init_paths || return 1

    section_header "User Env: Symlink dotfiles"

    # Backup and symlink gitconfig
    if [ -f "$USER_HOME/.gitconfig" ] && [ ! -L "$USER_HOME/.gitconfig" ]; then
        su - "$NEW_USERNAME" -c "mv -f $USER_HOME/.gitconfig $BACKUP_DIR/.gitconfig"
    fi
    su - "$NEW_USERNAME" -c "ln -sf $DOTFILES_DIR/git/gitconfig $USER_HOME/.gitconfig"
    log_info "Symlinked .gitconfig"

    # Symlink global gitignore
    su - "$NEW_USERNAME" -c "ln -sf $DOTFILES_DIR/git/gitignore_global $USER_HOME/.gitignore_global"
    log_info "Symlinked .gitignore_global"

    # Symlink p10k config if it exists
    if [ -f "$DOTFILES_DIR/zsh/p10k.zsh" ]; then
        su - "$NEW_USERNAME" -c "ln -sf $DOTFILES_DIR/zsh/p10k.zsh $USER_HOME/.p10k.zsh"
        log_info "Symlinked .p10k.zsh"
    fi

    # Symlink tmux.conf if it exists
    if [ -f "$DOTFILES_DIR/zsh/tmux.conf" ]; then
        if [ -f "$USER_HOME/.tmux.conf" ] && [ ! -L "$USER_HOME/.tmux.conf" ]; then
            su - "$NEW_USERNAME" -c "mv -f $USER_HOME/.tmux.conf $BACKUP_DIR/.tmux.conf"
        fi
        su - "$NEW_USERNAME" -c "ln -sf $DOTFILES_DIR/zsh/tmux.conf $USER_HOME/.tmux.conf"
        log_info "Symlinked .tmux.conf"
    fi

    mark_step_complete "user_env_symlinks"
}

user_env_ssh() {
    skip_if_complete "user_env_ssh" && return 0
    _user_env_init_paths || return 1

    section_header "User Env: SSH keys"
    local SSH_DIR="$USER_HOME/.ssh"
    su - "$NEW_USERNAME" -c "mkdir -p $SSH_DIR && chmod 700 $SSH_DIR"

    # Install authorized_keys from dotfiles if available
    if [ -f "$DOTFILES_DIR/vps/ssh-keys/authorized_keys" ]; then
        log_info "Installing SSH authorized keys..."
        su - "$NEW_USERNAME" -c "cp $DOTFILES_DIR/vps/ssh-keys/authorized_keys $SSH_DIR/authorized_keys && chmod 600 $SSH_DIR/authorized_keys"
        log_success "SSH authorized keys installed"
        echo "Authorized SSH keys installed from dotfiles" >> "$SETUP_INFO_FILE"
    else
        log_warning "No authorized_keys file found in dotfiles/vps/ssh-keys/"
    fi

    # Generate user's own SSH key (for GitHub/GitLab) if requested and missing
    if [ "$GENERATE_SSH_KEY" = "y" ]; then
        if [ ! -f "$SSH_DIR/id_ed25519" ]; then
            log_info "Generating ed25519 SSH key for $NEW_USERNAME (for GitHub/GitLab)..."
            su - "$NEW_USERNAME" -c "ssh-keygen -t ed25519 -C '$GIT_USER_EMAIL' -f $SSH_DIR/id_ed25519 -N ''"
            log_success "SSH key generated at $SSH_DIR/id_ed25519"

            echo "" >> "$SETUP_INFO_FILE"
            echo "=== USER SSH PUBLIC KEY ($NEW_USERNAME) ===" >> "$SETUP_INFO_FILE"
            su - "$NEW_USERNAME" -c "cat $SSH_DIR/id_ed25519.pub" >> "$SETUP_INFO_FILE"
            echo "========================================" >> "$SETUP_INFO_FILE"
            echo "" >> "$SETUP_INFO_FILE"
        else
            log_info "SSH key already exists for $NEW_USERNAME"
        fi
    else
        log_info "Skipping SSH key generation (GENERATE_SSH_KEY=n)"
    fi

    mark_step_complete "user_env_ssh"
}

user_env_zsh() {
    [ "$INSTALL_ZSH" = "y" ] || return 0
    skip_if_complete "user_env_zsh" && return 0
    _user_env_init_paths || return 1

    section_header "User Env: Zsh + Oh My Zsh + p10k"

    chsh -s "$(command -v zsh)" "$NEW_USERNAME"
    log_info "Changed default shell to zsh for $NEW_USERNAME"

    if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
        su - "$NEW_USERNAME" -c 'KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
        log_success "Installed Oh My Zsh for $NEW_USERNAME"
    fi

    local P10K_DIR="$USER_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    if [ ! -d "$P10K_DIR" ]; then
        log_info "Installing Powerlevel10k theme..."
        su - "$NEW_USERNAME" -c "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $P10K_DIR"
        log_success "Powerlevel10k theme installed"
    fi

    # Symlink zshrc AFTER Oh My Zsh so the OMZ default doesn't override
    if [ -f "$USER_HOME/.zshrc" ] && [ ! -L "$USER_HOME/.zshrc" ]; then
        su - "$NEW_USERNAME" -c "mv -f $USER_HOME/.zshrc $BACKUP_DIR/.zshrc.oh-my-zsh-default"
    fi
    su - "$NEW_USERNAME" -c "ln -sf $DOTFILES_DIR/zsh/zshrc $USER_HOME/.zshrc"
    log_success "Symlinked .zshrc"

    mark_step_complete "user_env_zsh"
}

user_env_zsh_plugins() {
    [ "$INSTALL_ZSH" = "y" ] || return 0
    skip_if_complete "user_env_zsh_plugins" && return 0
    _user_env_init_paths || return 1

    section_header "User Env: Zsh plugins"
    local ZSH_CUSTOM="$USER_HOME/.oh-my-zsh/custom"

    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
        log_info "Installing zsh-autosuggestions..."
        su - "$NEW_USERNAME" -c "git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions"
        log_success "zsh-autosuggestions installed"
    fi

    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
        log_info "Installing zsh-syntax-highlighting..."
        su - "$NEW_USERNAME" -c "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
        log_success "zsh-syntax-highlighting installed"
    fi

    mark_step_complete "user_env_zsh_plugins"
}

user_env_nvm() {
    [ "$INSTALL_NVM" = "y" ] || return 0
    skip_if_complete "user_env_nvm" && return 0
    _user_env_init_paths || return 1

    section_header "User Env: NVM + Node.js ${NODE_VERSION}"

    if [ ! -d "$USER_HOME/.nvm" ]; then
        log_info "Installing NVM for $NEW_USERNAME..."
        su - "$NEW_USERNAME" -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
        su - "$NEW_USERNAME" -c "export NVM_DIR=\"\$HOME/.nvm\" && [ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\" && nvm install ${NODE_VERSION} && nvm alias default ${NODE_VERSION} && nvm use default"
        log_success "NVM and Node.js ${NODE_VERSION} installed for $NEW_USERNAME"
    else
        log_info "NVM already installed for $NEW_USERNAME"
    fi

    mark_step_complete "user_env_nvm"
}

user_env_uv() {
    [ "$INSTALL_UV" = "y" ] || return 0
    skip_if_complete "user_env_uv" && return 0
    _user_env_init_paths || return 1

    section_header "User Env: UV + Python ${PYTHON_VERSION}"

    if [ ! -f "$USER_HOME/.local/bin/uv" ]; then
        log_info "Installing UV for $NEW_USERNAME..."
        su - "$NEW_USERNAME" -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
        su - "$NEW_USERNAME" -c "export PATH=\"\$HOME/.local/bin:\$PATH\" && uv python install ${PYTHON_VERSION}"
        log_success "UV and Python ${PYTHON_VERSION} installed for $NEW_USERNAME"
    else
        log_info "UV already installed for $NEW_USERNAME"
    fi

    mark_step_complete "user_env_uv"
}

user_env_bun() {
    [ "$INSTALL_BUN" = "y" ] || return 0
    skip_if_complete "user_env_bun" && return 0
    _user_env_init_paths || return 1

    section_header "User Env: Bun"

    # PATH expansion needed because `su - user -c` under zsh skips .zshrc
    if ! su - "$NEW_USERNAME" -c 'export PATH="$HOME/.bun/bin:$PATH"; command -v bun' &>/dev/null; then
        log_info "Installing Bun for $NEW_USERNAME..."
        su - "$NEW_USERNAME" -c 'curl -fsSL https://bun.sh/install | bash'
        log_success "Bun installed for $NEW_USERNAME"
    else
        log_info "Bun already installed for $NEW_USERNAME"
    fi

    mark_step_complete "user_env_bun"
}

user_env_claude() {
    [ "$INSTALL_CLAUDE" = "y" ] || return 0
    skip_if_complete "user_env_claude" && return 0
    _user_env_init_paths || return 1

    section_header "User Env: Claude Code"

    if su - "$NEW_USERNAME" -c 'export PATH="$HOME/.local/bin:$PATH"; command -v claude' &>/dev/null; then
        log_info "Claude Code already installed for $NEW_USERNAME, skipping"
    else
        log_info "Installing Claude Code for $NEW_USERNAME..."
        # set -o pipefail in the subshell so a failed curl propagates through `| bash`
        if su - "$NEW_USERNAME" -c 'set -o pipefail; curl -fsSL https://claude.ai/install.sh | bash'; then
            log_success "Claude Code installed for $NEW_USERNAME"
            log_info "User should run 'claude' then '/login' inside it to authenticate"
        else
            log_warning "Claude Code install failed (continuing anyway). User can retry with: curl -fsSL https://claude.ai/install.sh | bash"
        fi
    fi

    mark_step_complete "user_env_claude"
}

user_env_codex() {
    [ "$INSTALL_CODEX" = "y" ] || return 0
    [ "$INSTALL_NVM" = "y" ] || { log_warning "Skipping Codex install — requires NVM"; return 0; }
    skip_if_complete "user_env_codex" && return 0
    _user_env_init_paths || return 1

    section_header "User Env: OpenAI Codex CLI"

    # Codex installs as an npm global, so the bun-style PATH expansion isn't needed —
    # NVM puts node/npm/codex into the user's nvm directory, which `su - user`
    # picks up via the loaded NVM script.
    if su - "$NEW_USERNAME" -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && command -v codex' &>/dev/null; then
        log_info "Codex already installed for $NEW_USERNAME, skipping"
    else
        log_info "Installing OpenAI Codex CLI for $NEW_USERNAME..."
        if su - "$NEW_USERNAME" -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && npm install -g @openai/codex' 2>&1 | tee -a "$SETUP_INFO_FILE"; then
            log_success "OpenAI Codex installed for $NEW_USERNAME"
        else
            log_warning "Codex install failed (continuing anyway). User can retry with: npm install -g @openai/codex"
        fi
    fi

    mark_step_complete "user_env_codex"
}

user_env_npm_globals() {
    [ "$INSTALL_NVM" = "y" ] || return 0
    skip_if_complete "user_env_npm_globals" && return 0
    _user_env_init_paths || return 1

    section_header "User Env: npm globals (diff-so-fancy, pnpm)"

    log_info "Installing diff-so-fancy for $NEW_USERNAME..."
    su - "$NEW_USERNAME" -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && npm install -g diff-so-fancy' 2>&1 | tee -a "$SETUP_INFO_FILE" || log_warning "Failed to install diff-so-fancy"

    log_info "Installing pnpm for $NEW_USERNAME..."
    su - "$NEW_USERNAME" -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && npm install -g pnpm' 2>&1 | tee -a "$SETUP_INFO_FILE" || log_warning "Failed to install pnpm"

    mark_step_complete "user_env_npm_globals"
}

user_env_log_versions() {
    # Always re-run on resume; cheap and useful for the info file.
    _user_env_init_paths || return 1

    log_info "Logging installed tool versions..."
    if [ "$INSTALL_NVM" = "y" ]; then
        su - "$NEW_USERNAME" -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && node --version && npm --version && pnpm --version' >> "$SETUP_INFO_FILE" 2>&1 || true
    fi
    if [ "$INSTALL_UV" = "y" ]; then
        su - "$NEW_USERNAME" -c 'export PATH="$HOME/.local/bin:$PATH" && uv --version' >> "$SETUP_INFO_FILE" 2>&1 || true
    fi
    if [ "$INSTALL_BUN" = "y" ]; then
        su - "$NEW_USERNAME" -c 'export PATH="$HOME/.bun/bin:$PATH" && bun --version' >> "$SETUP_INFO_FILE" 2>&1 || true
    fi
    if [ "$INSTALL_CLAUDE" = "y" ]; then
        su - "$NEW_USERNAME" -c 'export PATH="$HOME/.local/bin:$PATH" && claude --version' >> "$SETUP_INFO_FILE" 2>&1 || true
    fi
}

install_user_environment() {
    # Thin orchestrator — each sub-step is individually resumable.
    section_header "Setting Up User Development Environment"
    _user_env_init_paths || return 1
    log_info "Using home directory: $USER_HOME"

    user_env_clone_dotfiles
    user_env_symlinks
    user_env_ssh
    user_env_zsh
    user_env_nvm
    user_env_uv
    user_env_bun
    user_env_claude
    user_env_codex
    user_env_npm_globals
    user_env_zsh_plugins
    user_env_log_versions

    log_success "User development environment configured for $NEW_USERNAME"
}

#####################################################
# Main Installation Flow
#####################################################

main() {
    check_root

    # Phase 1: Collect all inputs
    collect_user_inputs

    echo ""
    section_header "Starting Installation"
    log_info "Installation started at $(date)"

    # Phase 2: System preparation
    update_system
    check_ssh_keys

    # Phase 3: Create user early
    create_user

    # Phase 4: Install system packages and services (as root)
    [ "$INSTALL_TOOLS" = "y" ] && install_common_tools
    [ "$INSTALL_SECURITY" = "y" ] && install_security
    [ "$INSTALL_MOSH" = "y" ] && install_mosh
    [ "$INSTALL_ZSH" = "y" ] && install_zsh  # System package only
    [ "$INSTALL_DOCKER" = "y" ] && install_docker
    [ "$INSTALL_TAILSCALE" = "y" ] && install_tailscale
    [ "$SETUP_SWAP" = "y" ] && setup_swap_space

    # Phase 5: Install user development environment (as new user)
    [ "$INSTALL_DOTFILES" = "y" ] && install_user_environment

    # Phase 6: Final summary
    show_summary
}

generate_todo_content() {
    local content=""

    content+="========================================\n"
    content+="VPS Setup - Next Steps & TODO List\n"
    content+="========================================\n"
    content+="Installation completed: $(date)\n"
    content+="Server: $(hostname)\n"
    content+="User: $NEW_USERNAME\n"
    content+="========================================\n\n"

    content+="=== INSTALLED COMPONENTS ===\n\n"
    [ "$INSTALL_TOOLS" = "y" ] && content+="  ✓ Common development tools\n"
    [ "$INSTALL_SECURITY" = "y" ] && content+="  ✓ UFW firewall and fail2ban\n"
    [ "$INSTALL_MOSH" = "y" ] && content+="  ✓ Mosh (mobile shell — survives flaky networks)\n"
    [ "$INSTALL_ZSH" = "y" ] && content+="  ✓ Zsh + Oh My Zsh\n"
    [ "$INSTALL_UV" = "y" ] && content+="  ✓ UV with Python ${PYTHON_VERSION}\n"
    [ "$INSTALL_NVM" = "y" ] && content+="  ✓ NVM with Node.js ${NODE_VERSION}, pnpm, diff-so-fancy\n"
    [ "$INSTALL_DOCKER" = "y" ] && content+="  ✓ Docker + Docker Compose\n"
    [ "$INSTALL_TAILSCALE" = "y" ] && content+="  ✓ Tailscale VPN\n"
    [ "$INSTALL_BUN" = "y" ] && content+="  ✓ Bun\n"
    [ "$INSTALL_CLAUDE" = "y" ] && content+="  ✓ Claude Code CLI\n"
    [ "$INSTALL_CODEX" = "y" ] && content+="  ✓ OpenAI Codex CLI\n"
    [ "$SETUP_SWAP" = "y" ] && content+="  ✓ Swap space (${SWAP_SIZE}GB)\n"
    [ "$INSTALL_DOTFILES" = "y" ] && content+="  ✓ Dotfiles configuration\n"

    content+="\n========================================\n"
    content+="=== NEXT STEPS (IMPORTANT!) ===\n"
    content+="========================================\n\n"

    local step=1

    if [ "$CREATE_NEW_USER" = "y" ]; then
        content+="*** CRITICAL: CHANGE YOUR PASSWORD IMMEDIATELY ***\n\n"
        content+="$step. Login with temporary credentials:\n"
        content+="   ssh $NEW_USERNAME@your-server-ip\n"
        content+="   Password: $NEW_USERNAME\n\n"
        step=$((step + 1))
        content+="$step. Change your password immediately after login:\n"
        content+="   passwd\n\n"
        step=$((step + 1))
    fi

    content+="$step. Configure Powerlevel10k prompt (first login will trigger setup):\n"
    content+="   The configuration wizard will start automatically\n"
    content+="   Recommended: Enable transient prompt for clean history\n"
    content+="   To reconfigure later: p10k configure\n\n"
    step=$((step + 1))

    content+="$step. Add your SSH public key to GitHub/GitLab:\n"
    content+="   Your SSH key was auto-generated during setup\n"
    content+="   View it with: cat ~/.ssh/id_ed25519.pub\n"
    content+="   Then add it to:\n"
    content+="   - GitHub: https://github.com/settings/keys\n"
    content+="   - GitLab: https://gitlab.com/-/profile/keys\n\n"
    step=$((step + 1))

    if [ "$INSTALL_TAILSCALE" = "y" ]; then
        content+="$step. Connect to Tailscale VPN:\n"
        content+="   sudo tailscale up\n\n"
        step=$((step + 1))
    fi

    if [ "$INSTALL_CLAUDE" = "y" ]; then
        content+="$step. Authenticate Claude Code:\n"
        content+="   Run 'claude' to launch, then type '/login' to authenticate\n\n"
        step=$((step + 1))
    fi

    content+="$step. Consider SSH hardening (IMPORTANT):\n"
    content+="   - Change SSH port from 22 to custom (e.g., 2222)\n"
    content+="   - Set 'PermitRootLogin no' in /etc/ssh/sshd_config\n"
    content+="   - Set 'PasswordAuthentication no' (after setting up SSH keys)\n\n"
    content+="   Commands:\n"
    content+="   sudo vim /etc/ssh/sshd_config\n"
    content+="   sudo systemctl restart sshd\n\n"
    step=$((step + 1))

    if [ "$INSTALL_SECURITY" = "y" ]; then
        content+="$step. Update UFW if you changed SSH port:\n"
        content+="   sudo ufw allow 2222/tcp\n"
        content+="   sudo ufw delete allow 22/tcp\n\n"
        step=$((step + 1))
    fi

    content+="$step. Reboot the system to apply all changes:\n"
    content+="   sudo reboot\n\n"

    content+="========================================\n"
    content+="=== IMPORTANT FILES ===\n"
    content+="========================================\n\n"
    content+="- Setup details: /root/vps-setup-info.txt\n"
    content+="- This TODO list: ~/after_setup_todo.txt\n"
    content+="- Dotfiles: ~/dotfiles\n"
    content+="- Zsh config: ~/.zshrc -> ~/dotfiles/zsh/zshrc\n"
    content+="- Git config: ~/.gitconfig -> ~/dotfiles/git/gitconfig\n\n"

    if [ -f /root/.ssh/id_ed25519.pub ]; then
        content+="========================================\n"
        content+="=== SSH KEYS NOTE ===\n"
        content+="========================================\n\n"
        content+="Root SSH key was generated for system use.\n"
        content+="Each user should generate their own SSH keys (see step 3 above).\n\n"
        content+="Root public key location: /root/.ssh/id_ed25519.pub\n\n"
    fi

    content+="========================================\n"
    content+="=== USEFUL ALIASES ===\n"
    content+="========================================\n\n"
    content+="Docker Compose:\n"
    content+="  dc         - docker compose\n"
    content+="  up         - docker compose up -d\n"
    content+="  down       - docker compose down\n"
    content+="  dlog       - docker compose logs -f --tail 300\n"
    content+="  dcr        - docker compose down && docker compose up -d\n"
    content+="  dcupdate   - docker compose up -d --no-deps --pull always\n\n"
    content+="Claude Code:\n"
    content+="  cc         - claude --dangerously-skip-permissions\n\n"
    content+="Tmux:\n"
    content+="  t          - tmux\n"
    content+="  ta         - tmux attach\n"
    content+="  tls        - tmux ls\n"
    content+="  tn         - tmux new -s\n"
    content+="  tat        - tmux attach -t\n\n"
    content+="Git:\n"
    content+="  st         - git status\n"
    content+="  co         - git checkout\n"
    content+="  cm         - git commit\n"
    content+="  br         - git branch\n"
    content+="  lg         - git log with graph\n"
    content+="  pushf      - git push -f origin\n\n"
    content+="========================================\n\n"
    content+="You can delete this file once you've completed all steps:\n"
    content+="  rm ~/after_setup_todo.txt\n\n"
    content+="Enjoy your new VPS! 🚀\n\n"
    content+="========================================\n"

    echo "$content"
}

show_summary() {
    section_header "Installation Complete!"

    echo -e "${GREEN}✓ VPS setup completed successfully${NC}"
    echo ""
    echo "Installation details saved to: $SETUP_INFO_FILE"
    echo ""

    # Generate todo content once
    TODO_CONTENT=$(generate_todo_content)

    # Display to console with yellow color
    echo -e "${YELLOW}$TODO_CONTENT${NC}"

    # Log summary
    echo "" >> "$SETUP_INFO_FILE"
    echo "========================================" >> "$SETUP_INFO_FILE"
    echo "Installation completed at $(date)" >> "$SETUP_INFO_FILE"
    echo "User created: $NEW_USERNAME" >> "$SETUP_INFO_FILE"
    echo "========================================" >> "$SETUP_INFO_FILE"

    # Create after_setup_todo.txt in user's home directory (dynamically detected)
    USER_HOME=$(getent passwd "$NEW_USERNAME" | cut -d: -f6)
    if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
        log_warning "Could not detect home for $NEW_USERNAME, falling back to /home/$NEW_USERNAME"
        USER_HOME="/home/$NEW_USERNAME"
    fi
    TODO_FILE="$USER_HOME/after_setup_todo.txt"

    log_info "Creating after setup todo list at $TODO_FILE..."

    # Write the same content to file (use -e to interpret escape sequences)
    echo -e "$TODO_CONTENT" > "$TODO_FILE"

    # Set ownership to new user
    chown "$NEW_USERNAME:$NEW_USERNAME" "$TODO_FILE"
    chmod 644 "$TODO_FILE"

    log_success "After setup todo list created at $TODO_FILE"
    echo ""
    echo -e "${GREEN}📝 A detailed todo list has been saved to: ${BLUE}$TODO_FILE${NC}"
    echo -e "${YELLOW}   View it anytime with: ${BLUE}cat ~/after_setup_todo.txt${NC}"

    # Clean up state file on successful completion
    log_info "Cleaning up state file..."
    rm -f "$STATE_FILE"
    log_success "Installation state cleaned up"
}

#####################################################
# Script Entry Point
#####################################################

main "$@"
