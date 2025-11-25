#!/bin/bash

#####################################################
# VPS Setup Script - Complete Server Configuration
#####################################################
# Usage: curl -fsSL <your-url>/setup-vps.sh | sudo bash
# Or: sudo bash setup-vps.sh
#####################################################

set -e

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

collect_user_inputs() {
    section_header "VPS Setup Configuration"

    echo -e "${GREEN}Welcome to the VPS Setup Script!${NC}"
    echo "This script will configure your server with selected components."
    echo ""

    # Check if resuming from previous run
    if [ -f "$STATE_FILE" ]; then
        echo -e "${YELLOW}Previous installation detected!${NC}"
        echo ""
        read -p "Resume previous installation? (y/n): " RESUME_INSTALL </dev/tty
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

    # Collect new username
    while true; do
        read -p "Enter username for new user account: " NEW_USERNAME </dev/tty
        if [ -z "$NEW_USERNAME" ]; then
            log_warning "Username cannot be empty"
            continue
        fi
        if id "$NEW_USERNAME" &>/dev/null; then
            log_warning "User $NEW_USERNAME already exists"
            read -p "Continue with existing user? (y/n): " confirm </dev/tty
            if [ "$confirm" = "y" ]; then
                break
            fi
        else
            break
        fi
    done

    # Collect git configuration
    read -p "Enter Git user name (e.g., 'Eric'): " GIT_USER_NAME </dev/tty
    read -p "Enter Git email (e.g., 'your@email.com'): " GIT_USER_EMAIL </dev/tty

    # Component selection
    echo ""
    echo -e "${YELLOW}Select components to install (y/n for each):${NC}"
    echo ""

    read -p "Install common tools (curl, wget, git, vim, htop, unzip, tree, build-essential)? [Y/n]: " INSTALL_TOOLS </dev/tty
    INSTALL_TOOLS=${INSTALL_TOOLS:-y}

    read -p "Install security tools (UFW firewall + fail2ban)? [Y/n]: " INSTALL_SECURITY </dev/tty
    INSTALL_SECURITY=${INSTALL_SECURITY:-y}

    read -p "Install Zsh + Oh My Zsh? [Y/n]: " INSTALL_ZSH </dev/tty
    INSTALL_ZSH=${INSTALL_ZSH:-y}

    read -p "Install UV (Python package manager) with Python 3.12? [Y/n]: " INSTALL_UV </dev/tty
    INSTALL_UV=${INSTALL_UV:-y}

    read -p "Install NVM with Node.js 22? [Y/n]: " INSTALL_NVM </dev/tty
    INSTALL_NVM=${INSTALL_NVM:-y}

    read -p "Install Docker + Docker Compose? [Y/n]: " INSTALL_DOCKER </dev/tty
    INSTALL_DOCKER=${INSTALL_DOCKER:-y}

    read -p "Install Tailscale VPN? [Y/n]: " INSTALL_TAILSCALE </dev/tty
    INSTALL_TAILSCALE=${INSTALL_TAILSCALE:-y}

    read -p "Install Claude Code CLI? [Y/n]: " INSTALL_CLAUDE </dev/tty
    INSTALL_CLAUDE=${INSTALL_CLAUDE:-y}

    read -p "Configure swap space (recommended for low-memory VPS)? [Y/n]: " SETUP_SWAP </dev/tty
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
        read -p "Swap size in GB [recommended: ${RECOMMENDED_SWAP}]: " SWAP_SIZE </dev/tty
        SWAP_SIZE=${SWAP_SIZE:-$RECOMMENDED_SWAP}
    fi

    read -p "Clone and apply dotfiles from github.com/tanker327? [Y/n]: " INSTALL_DOTFILES </dev/tty
    INSTALL_DOTFILES=${INSTALL_DOTFILES:-y}

    # Summary of selections
    echo ""
    section_header "Configuration Summary"
    echo -e "${GREEN}Username:${NC} $NEW_USERNAME"
    echo -e "${GREEN}Git Config:${NC} $GIT_USER_NAME <$GIT_USER_EMAIL>"
    echo ""
    echo "Components to install:"
    [ "$INSTALL_TOOLS" = "y" ] && echo "   Common tools"
    [ "$INSTALL_SECURITY" = "y" ] && echo "   Security (UFW + fail2ban)"
    [ "$INSTALL_ZSH" = "y" ] && echo "   Zsh + Oh My Zsh"
    [ "$INSTALL_UV" = "y" ] && echo "   UV (Python 3.12)"
    [ "$INSTALL_NVM" = "y" ] && echo "   NVM (Node.js 22)"
    [ "$INSTALL_DOCKER" = "y" ] && echo "   Docker + Docker Compose"
    [ "$INSTALL_TAILSCALE" = "y" ] && echo "   Tailscale VPN"
    [ "$INSTALL_CLAUDE" = "y" ] && echo "   Claude Code"
    [ "$SETUP_SWAP" = "y" ] && echo "   Swap space (${SWAP_SIZE}GB)"
    [ "$INSTALL_DOTFILES" = "y" ] && echo "   Dotfiles configuration"
    echo ""

    read -p "Proceed with installation? (y/n): " CONFIRM_INSTALL </dev/tty
    if [ "$CONFIRM_INSTALL" != "y" ]; then
        log_warning "Installation cancelled by user"
        exit 0
    fi

    # Save configuration to state file
    cat > "$STATE_FILE" <<EOF
# VPS Setup Configuration - $(date)
NEW_USERNAME="$NEW_USERNAME"
GIT_USER_NAME="$GIT_USER_NAME"
GIT_USER_EMAIL="$GIT_USER_EMAIL"
INSTALL_TOOLS="$INSTALL_TOOLS"
INSTALL_SECURITY="$INSTALL_SECURITY"
INSTALL_ZSH="$INSTALL_ZSH"
INSTALL_UV="$INSTALL_UV"
INSTALL_NVM="$INSTALL_NVM"
INSTALL_DOCKER="$INSTALL_DOCKER"
INSTALL_TAILSCALE="$INSTALL_TAILSCALE"
INSTALL_CLAUDE="$INSTALL_CLAUDE"
SETUP_SWAP="$SETUP_SWAP"
SWAP_SIZE="$SWAP_SIZE"
INSTALL_DOTFILES="$INSTALL_DOTFILES"
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
    log_info "Installing curl, wget, git, vim, htop, unzip, tree, build-essential..."
    apt install -y curl wget git vim htop unzip tree build-essential net-tools locate openssh-server openssh-client
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

install_zsh() {
    skip_if_complete "install_zsh" && return 0

    section_header "Installing Zsh + Oh My Zsh"

    log_info "Installing Zsh..."
    apt install -y zsh

    log_info "Installing Oh My Zsh for root..."
    if [ ! -d /root/.oh-my-zsh ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        log_success "Oh My Zsh installed for root"
    else
        log_info "Oh My Zsh already installed for root"
    fi

    # Change default shell for root
    chsh -s $(which zsh) root

    log_success "Zsh configured"

    mark_step_complete "install_zsh"
}

install_uv_python() {
    skip_if_complete "install_uv_python" && return 0

    section_header "Installing UV (Python Package Manager)"

    log_info "Installing UV..."
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # Source UV for current session
    export PATH="$HOME/.local/bin:$PATH"

    log_info "Installing Python 3.12 via UV..."
    if command -v uv &> /dev/null; then
        uv python install 3.12
        log_success "UV and Python 3.12 installed"
        echo "UV_PYTHON_VERSION=3.12" >> "$SETUP_INFO_FILE"
    else
        log_error "UV installation failed or not in PATH"
    fi

    mark_step_complete "install_uv_python"
}

install_nvm_node() {
    skip_if_complete "install_nvm_node" && return 0

    section_header "Installing NVM + Node.js 22"

    log_info "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

    # Source NVM for current session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    log_info "Installing Node.js 22..."
    if [ -d "$NVM_DIR" ]; then
        nvm install 22
        nvm alias default 22
        nvm use default
        log_success "NVM and Node.js 22 installed"
        node --version >> "$SETUP_INFO_FILE"
        npm --version >> "$SETUP_INFO_FILE"
    else
        log_error "NVM installation failed"
    fi

    mark_step_complete "install_nvm_node"
}

install_docker() {
    skip_if_complete "install_docker" && return 0

    section_header "Installing Docker + Docker Compose"

    log_info "Installing Docker prerequisites..."
    apt install -y apt-transport-https ca-certificates gnupg lsb-release

    log_info "Adding Docker GPG key and repository..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
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

install_claude_code() {
    skip_if_complete "install_claude_code" && return 0

    section_header "Installing Claude Code CLI"

    log_info "Installing Claude Code..."
    curl -fsSL https://installs.claude.ai/install.sh | sh

    log_success "Claude Code installed"
    log_info "Run 'claude auth' to authenticate Claude Code"

    mark_step_complete "install_claude_code"
}

setup_swap_space() {
    skip_if_complete "setup_swap_space" && return 0

    section_header "Setting Up Swap Space"

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

install_dotfiles() {
    skip_if_complete "install_dotfiles" && return 0

    section_header "Installing Dotfiles Configuration"

    USER_HOME="/home/$NEW_USERNAME"
    DOTFILES_DIR="$USER_HOME/dotfiles"

    log_info "Cloning dotfiles repository..."
    if [ -d "$DOTFILES_DIR" ]; then
        log_warning "Dotfiles directory already exists"
        rm -rf "$DOTFILES_DIR"
    fi

    # Clone as the new user
    su - "$NEW_USERNAME" -c "git clone https://github.com/tanker327/dotfiles.git $DOTFILES_DIR"

    if [ ! -d "$DOTFILES_DIR" ]; then
        log_error "Failed to clone dotfiles repository"
        return 1
    fi

    log_info "Configuring Git..."
    su - "$NEW_USERNAME" -c "git config --global user.name '$GIT_USER_NAME'"
    su - "$NEW_USERNAME" -c "git config --global user.email '$GIT_USER_EMAIL'"

    # Create backup directory
    BACKUP_DIR="$USER_HOME/.backup"
    su - "$NEW_USERNAME" -c "mkdir -p $BACKUP_DIR"

    log_info "Applying dotfiles configurations..."

    # Backup and symlink zshrc
    if [ -f "$USER_HOME/.zshrc" ]; then
        su - "$NEW_USERNAME" -c "mv -f $USER_HOME/.zshrc $BACKUP_DIR/.zshrc"
    fi
    su - "$NEW_USERNAME" -c "ln -sf $DOTFILES_DIR/zsh/zshrc $USER_HOME/.zshrc"
    log_info "Symlinked .zshrc"

    # Backup and symlink gitconfig
    if [ -f "$USER_HOME/.gitconfig" ]; then
        su - "$NEW_USERNAME" -c "mv -f $USER_HOME/.gitconfig $BACKUP_DIR/.gitconfig"
    fi
    su - "$NEW_USERNAME" -c "ln -sf $DOTFILES_DIR/git/gitconfig $USER_HOME/.gitconfig"
    log_info "Symlinked .gitconfig"

    # Symlink global gitignore
    su - "$NEW_USERNAME" -c "ln -sf $DOTFILES_DIR/git/gitignore_global $USER_HOME/.gitignore_global"
    log_info "Symlinked .gitignore_global"

    # Configure SSH authorized_keys
    if [ -f "$DOTFILES_DIR/vps/ssh-keys/authorized_keys" ]; then
        log_info "Installing SSH authorized keys..."
        SSH_DIR="$USER_HOME/.ssh"
        su - "$NEW_USERNAME" -c "mkdir -p $SSH_DIR"
        su - "$NEW_USERNAME" -c "chmod 700 $SSH_DIR"
        su - "$NEW_USERNAME" -c "cp $DOTFILES_DIR/vps/ssh-keys/authorized_keys $SSH_DIR/authorized_keys"
        su - "$NEW_USERNAME" -c "chmod 600 $SSH_DIR/authorized_keys"
        log_success "SSH authorized keys installed"
        echo "Authorized SSH keys installed from dotfiles" >> "$SETUP_INFO_FILE"
    else
        log_warning "No authorized_keys file found in dotfiles/vps/ssh-keys/"
    fi

    # Change default shell to zsh for new user
    if [ "$INSTALL_ZSH" = "y" ]; then
        chsh -s $(which zsh) "$NEW_USERNAME"
        log_info "Changed default shell to zsh for $NEW_USERNAME"

        # Install Oh My Zsh for new user
        if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
            su - "$NEW_USERNAME" -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
            log_info "Installed Oh My Zsh for $NEW_USERNAME"
        fi
    fi

    log_success "Dotfiles configured for $NEW_USERNAME"

    mark_step_complete "install_dotfiles"
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

    # Phase 3: Create user first
    create_user

    # Phase 4: Install selected components
    [ "$INSTALL_TOOLS" = "y" ] && install_common_tools
    [ "$INSTALL_SECURITY" = "y" ] && install_security
    [ "$INSTALL_ZSH" = "y" ] && install_zsh
    [ "$INSTALL_UV" = "y" ] && install_uv_python
    [ "$INSTALL_NVM" = "y" ] && install_nvm_node
    [ "$INSTALL_DOCKER" = "y" ] && install_docker
    [ "$INSTALL_TAILSCALE" = "y" ] && install_tailscale
    [ "$INSTALL_CLAUDE" = "y" ] && install_claude_code
    [ "$SETUP_SWAP" = "y" ] && setup_swap_space
    [ "$INSTALL_DOTFILES" = "y" ] && install_dotfiles

    # Phase 5: Final summary
    show_summary
}

show_summary() {
    section_header "Installation Complete!"

    echo -e "${GREEN} VPS setup completed successfully${NC}"
    echo ""
    echo "Installation details saved to: $SETUP_INFO_FILE"
    echo ""

    echo -e "${YELLOW}=== Installed Components ===${NC}"
    [ "$INSTALL_TOOLS" = "y" ] && echo "   Common development tools"
    [ "$INSTALL_SECURITY" = "y" ] && echo "   UFW firewall and fail2ban"
    [ "$INSTALL_ZSH" = "y" ] && echo "   Zsh + Oh My Zsh"
    [ "$INSTALL_UV" = "y" ] && echo "   UV with Python 3.12"
    [ "$INSTALL_NVM" = "y" ] && echo "   NVM with Node.js 22"
    [ "$INSTALL_DOCKER" = "y" ] && echo "   Docker + Docker Compose"
    [ "$INSTALL_TAILSCALE" = "y" ] && echo "   Tailscale VPN"
    [ "$INSTALL_CLAUDE" = "y" ] && echo "   Claude Code CLI"
    [ "$SETUP_SWAP" = "y" ] && echo "   Swap space (${SWAP_SIZE}GB)"
    [ "$INSTALL_DOTFILES" = "y" ] && echo "   Dotfiles configuration"
    echo ""

    echo -e "${YELLOW}=== Next Steps ===${NC}"
    echo ""
    echo -e "${RED}*** IMPORTANT: CHANGE YOUR PASSWORD IMMEDIATELY ***${NC}"
    echo "1. Login with temporary credentials:"
    echo -e "   ${BLUE}ssh $NEW_USERNAME@your-server-ip${NC}"
    echo -e "   ${YELLOW}Password: $NEW_USERNAME${NC}"
    echo ""
    echo "2. Change your password immediately after login:"
    echo -e "   ${BLUE}passwd${NC}"
    echo ""

    echo "3. Generate SSH keys for $NEW_USERNAME (for GitHub/GitLab):"
    echo -e "   ${BLUE}ssh-keygen -t ed25519 -C \"$GIT_USER_EMAIL\"${NC}"
    echo -e "   ${BLUE}cat ~/.ssh/id_ed25519.pub${NC}"
    echo "   Add the public key to GitHub/GitLab"
    echo ""

    if [ "$INSTALL_TAILSCALE" = "y" ]; then
        echo "4. Connect to Tailscale VPN:"
        echo -e "   ${BLUE}sudo tailscale up${NC}"
        echo ""
    fi

    if [ "$INSTALL_CLAUDE" = "y" ]; then
        echo "5. Authenticate Claude Code:"
        echo -e "   ${BLUE}claude auth${NC}"
        echo ""
    fi

    echo "6. Consider SSH hardening (IMPORTANT):"
    echo "   - Change SSH port from 22 to custom (e.g., 2222)"
    echo "   - Set 'PermitRootLogin no' in /etc/ssh/sshd_config"
    echo "   - Set 'PasswordAuthentication no' (after setting up SSH keys)"
    echo -e "   ${BLUE}sudo vim /etc/ssh/sshd_config${NC}"
    echo -e "   ${BLUE}sudo systemctl restart sshd${NC}"
    echo ""

    if [ "$INSTALL_SECURITY" = "y" ]; then
        echo "7. Update UFW if you changed SSH port:"
        echo -e "   ${BLUE}sudo ufw allow 2222/tcp${NC}"
        echo -e "   ${BLUE}sudo ufw delete allow 22/tcp${NC}"
        echo ""
    fi

    echo "8. Reboot the system to apply all changes:"
    echo -e "   ${BLUE}sudo reboot${NC}"
    echo ""

    if [ -f /root/.ssh/id_ed25519.pub ]; then
        echo -e "${YELLOW}Note: Root SSH key was generated for system use.${NC}"
        echo "Each user should generate their own SSH keys (see step 2 above)."
        echo ""
    fi

    echo -e "${GREEN}Enjoy your new VPS! =�${NC}"

    # Log summary
    echo "" >> "$SETUP_INFO_FILE"
    echo "========================================" >> "$SETUP_INFO_FILE"
    echo "Installation completed at $(date)" >> "$SETUP_INFO_FILE"
    echo "User created: $NEW_USERNAME" >> "$SETUP_INFO_FILE"
    echo "========================================" >> "$SETUP_INFO_FILE"

    # Clean up state file on successful completion
    log_info "Cleaning up state file..."
    rm -f "$STATE_FILE"
    log_success "Installation state cleaned up"
}

#####################################################
# Script Entry Point
#####################################################

main "$@"
