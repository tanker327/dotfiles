#!/bin/bash

VERSION="1.0.0"

#####################################################
# macOS Setup Script - Complete Development Environment
#####################################################
# Usage: bash mac/setup-mac.sh
#####################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log and state files
SETUP_INFO_FILE="$HOME/.mac-setup-info.txt"
STATE_FILE="$HOME/.mac-setup-state"

# Dotfiles directory (detect from script location or use default)
DOTFILES_DIR="$HOME/dotfiles"
BACKUP_DIR="$HOME/.backup"

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

check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is intended for macOS only"
        exit 1
    fi
}

check_not_root() {
    if [ "$EUID" -eq 0 ]; then
        log_error "Do not run this script as root. Run as your normal user."
        exit 1
    fi
}

#####################################################
# Input Collection Phase
#####################################################

collect_user_inputs() {
    section_header "macOS Setup Configuration (Version $VERSION)"

    echo -e "${GREEN}Welcome to the macOS Setup Script!${NC}"
    echo "This script will configure your Mac with selected components."
    echo ""

    # Check if resuming from previous run
    if [ -f "$STATE_FILE" ]; then
        echo -e "${YELLOW}Previous installation detected!${NC}"
        echo ""
        read -p "Resume previous installation? (y/n): " RESUME_INSTALL </dev/tty
        if [ "$RESUME_INSTALL" = "y" ]; then
            log_info "Resuming previous installation..."
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
    echo "macOS Setup - $(date)" > "$SETUP_INFO_FILE"
    echo "========================================" >> "$SETUP_INFO_FILE"
    echo "" >> "$SETUP_INFO_FILE"

    # Git configuration
    read -p "Enter Git user name (e.g., 'Eric'): " GIT_USER_NAME </dev/tty
    read -p "Enter Git email (e.g., 'your@email.com'): " GIT_USER_EMAIL </dev/tty

    # Component selection
    echo ""
    echo -e "${YELLOW}Select components to install (y/n for each):${NC}"
    echo ""

    read -p "Install Homebrew (required for most components)? [Y/n]: " INSTALL_HOMEBREW </dev/tty
    INSTALL_HOMEBREW=${INSTALL_HOMEBREW:-y}

    read -p "Install common CLI tools (coreutils, git, vim, htop, tree, etc.)? [Y/n]: " INSTALL_TOOLS </dev/tty
    INSTALL_TOOLS=${INSTALL_TOOLS:-y}

    read -p "Install Zsh + Oh My Zsh + Powerlevel10k? [Y/n]: " INSTALL_ZSH </dev/tty
    INSTALL_ZSH=${INSTALL_ZSH:-y}

    read -p "Install UV (Python package manager) with Python 3.12? [Y/n]: " INSTALL_UV </dev/tty
    INSTALL_UV=${INSTALL_UV:-y}

    read -p "Install NVM with Node.js 22? [Y/n]: " INSTALL_NVM </dev/tty
    INSTALL_NVM=${INSTALL_NVM:-y}

    read -p "Install Docker Desktop? [Y/n]: " INSTALL_DOCKER </dev/tty
    INSTALL_DOCKER=${INSTALL_DOCKER:-y}

    read -p "Install Tailscale VPN? [Y/n]: " INSTALL_TAILSCALE </dev/tty
    INSTALL_TAILSCALE=${INSTALL_TAILSCALE:-y}

    read -p "Install Claude Code CLI? [Y/n]: " INSTALL_CLAUDE </dev/tty
    INSTALL_CLAUDE=${INSTALL_CLAUDE:-y}

    # Cask apps selection
    echo ""
    echo -e "${YELLOW}Select GUI applications to install:${NC}"
    echo ""

    read -p "Install iTerm2? [Y/n]: " INSTALL_ITERM2 </dev/tty
    INSTALL_ITERM2=${INSTALL_ITERM2:-y}

    read -p "Install Visual Studio Code? [Y/n]: " INSTALL_VSCODE </dev/tty
    INSTALL_VSCODE=${INSTALL_VSCODE:-y}

    read -p "Install Sublime Text? [Y/n]: " INSTALL_SUBLIME </dev/tty
    INSTALL_SUBLIME=${INSTALL_SUBLIME:-y}

    read -p "Install DBeaver (database tool)? [Y/n]: " INSTALL_DBEAVER </dev/tty
    INSTALL_DBEAVER=${INSTALL_DBEAVER:-y}

    read -p "Install Google Chrome? [Y/n]: " INSTALL_CHROME </dev/tty
    INSTALL_CHROME=${INSTALL_CHROME:-y}

    read -p "Install Alfred? [Y/n]: " INSTALL_ALFRED </dev/tty
    INSTALL_ALFRED=${INSTALL_ALFRED:-y}

    read -p "Install Obsidian? [Y/n]: " INSTALL_OBSIDIAN </dev/tty
    INSTALL_OBSIDIAN=${INSTALL_OBSIDIAN:-y}

    # Dotfiles
    echo ""
    read -p "Clone and apply dotfiles from github.com/tanker327? [Y/n]: " INSTALL_DOTFILES </dev/tty
    INSTALL_DOTFILES=${INSTALL_DOTFILES:-y}

    read -p "Generate SSH key (ED25519)? [Y/n]: " GENERATE_SSH_KEY </dev/tty
    GENERATE_SSH_KEY=${GENERATE_SSH_KEY:-y}

    # Summary of selections
    echo ""
    section_header "Configuration Summary"
    echo -e "${GREEN}Git Config:${NC} $GIT_USER_NAME <$GIT_USER_EMAIL>"
    echo ""
    echo "Components to install:"
    [ "$INSTALL_HOMEBREW" = "y" ] && echo "   Homebrew"
    [ "$INSTALL_TOOLS" = "y" ] && echo "   Common CLI tools"
    [ "$INSTALL_ZSH" = "y" ] && echo "   Zsh + Oh My Zsh + Powerlevel10k"
    [ "$INSTALL_UV" = "y" ] && echo "   UV (Python 3.12)"
    [ "$INSTALL_NVM" = "y" ] && echo "   NVM (Node.js 22)"
    [ "$INSTALL_DOCKER" = "y" ] && echo "   Docker Desktop"
    [ "$INSTALL_TAILSCALE" = "y" ] && echo "   Tailscale VPN"
    [ "$INSTALL_CLAUDE" = "y" ] && echo "   Claude Code CLI"
    echo ""
    echo "GUI Applications:"
    [ "$INSTALL_ITERM2" = "y" ] && echo "   iTerm2"
    [ "$INSTALL_VSCODE" = "y" ] && echo "   Visual Studio Code"
    [ "$INSTALL_SUBLIME" = "y" ] && echo "   Sublime Text"
    [ "$INSTALL_DBEAVER" = "y" ] && echo "   DBeaver"
    [ "$INSTALL_CHROME" = "y" ] && echo "   Google Chrome"
    [ "$INSTALL_ALFRED" = "y" ] && echo "   Alfred"
    [ "$INSTALL_OBSIDIAN" = "y" ] && echo "   Obsidian"
    echo ""
    [ "$INSTALL_DOTFILES" = "y" ] && echo "   Dotfiles configuration"
    [ "$GENERATE_SSH_KEY" = "y" ] && echo "   SSH key generation"
    echo ""

    read -p "Proceed with installation? (y/n): " CONFIRM_INSTALL </dev/tty
    if [ "$CONFIRM_INSTALL" != "y" ]; then
        log_warning "Installation cancelled by user"
        exit 0
    fi

    # Save configuration to state file
    cat > "$STATE_FILE" <<EOF
# macOS Setup Configuration - $(date)
GIT_USER_NAME="$GIT_USER_NAME"
GIT_USER_EMAIL="$GIT_USER_EMAIL"
INSTALL_HOMEBREW="$INSTALL_HOMEBREW"
INSTALL_TOOLS="$INSTALL_TOOLS"
INSTALL_ZSH="$INSTALL_ZSH"
INSTALL_UV="$INSTALL_UV"
INSTALL_NVM="$INSTALL_NVM"
INSTALL_DOCKER="$INSTALL_DOCKER"
INSTALL_TAILSCALE="$INSTALL_TAILSCALE"
INSTALL_CLAUDE="$INSTALL_CLAUDE"
INSTALL_ITERM2="$INSTALL_ITERM2"
INSTALL_VSCODE="$INSTALL_VSCODE"
INSTALL_SUBLIME="$INSTALL_SUBLIME"
INSTALL_DBEAVER="$INSTALL_DBEAVER"
INSTALL_CHROME="$INSTALL_CHROME"
INSTALL_ALFRED="$INSTALL_ALFRED"
INSTALL_OBSIDIAN="$INSTALL_OBSIDIAN"
INSTALL_DOTFILES="$INSTALL_DOTFILES"
GENERATE_SSH_KEY="$GENERATE_SSH_KEY"
EOF
    log_success "Configuration saved to $STATE_FILE"
}

#####################################################
# Installation Functions
#####################################################

install_homebrew() {
    skip_if_complete "install_homebrew" && return 0

    section_header "Installing Homebrew"

    if command -v brew &> /dev/null; then
        log_info "Homebrew already installed, updating..."
        brew update
    else
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add brew to PATH for Apple Silicon Macs
        if [ -f "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            log_info "Configured Homebrew for Apple Silicon"
        fi
    fi

    brew upgrade
    log_success "Homebrew ready"

    mark_step_complete "install_homebrew"
}

install_common_tools() {
    skip_if_complete "install_common_tools" && return 0

    section_header "Installing Common CLI Tools"

    local tools=(
        coreutils
        findutils
        gnu-sed
        curl
        wget
        git
        git-extras
        vim
        htop
        btop
        unzip
        tree
        tig
        diff-so-fancy
        imagemagick
        rename
        terminal-notifier
        ffmpeg
    )

    log_info "Installing CLI tools: ${tools[*]}"
    for tool in "${tools[@]}"; do
        if brew list "$tool" &>/dev/null; then
            log_info "$tool already installed"
        else
            log_info "Installing $tool..."
            brew install "$tool" || log_warning "Failed to install $tool"
        fi
    done

    log_success "Common CLI tools installed"

    mark_step_complete "install_common_tools"
}

install_zsh_environment() {
    skip_if_complete "install_zsh_environment" && return 0

    section_header "Installing Zsh + Oh My Zsh + Powerlevel10k"

    # macOS ships with zsh, but install latest via brew
    if ! brew list zsh &>/dev/null; then
        log_info "Installing latest Zsh via Homebrew..."
        brew install zsh
    else
        log_info "Zsh already installed via Homebrew"
    fi

    # Install Oh My Zsh
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log_info "Installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        log_success "Oh My Zsh installed"
    else
        log_info "Oh My Zsh already installed"
    fi

    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    # Install Powerlevel10k theme
    if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
        log_info "Installing Powerlevel10k theme..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
        log_success "Powerlevel10k installed"
    else
        log_info "Powerlevel10k already installed"
    fi

    # Install zsh-autosuggestions
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
        log_info "Installing zsh-autosuggestions..."
        git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
        log_success "zsh-autosuggestions installed"
    else
        log_info "zsh-autosuggestions already installed"
    fi

    # Install zsh-syntax-highlighting
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
        log_info "Installing zsh-syntax-highlighting..."
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
        log_success "zsh-syntax-highlighting installed"
    else
        log_info "zsh-syntax-highlighting already installed"
    fi

    log_success "Zsh environment configured"

    mark_step_complete "install_zsh_environment"
}

install_uv() {
    skip_if_complete "install_uv" && return 0

    section_header "Installing UV + Python 3.12"

    if command -v uv &> /dev/null; then
        log_info "UV already installed"
    else
        log_info "Installing UV..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi

    log_info "Installing Python 3.12 via UV..."
    uv python install 3.12
    log_success "UV and Python 3.12 installed"

    mark_step_complete "install_uv"
}

install_nvm() {
    skip_if_complete "install_nvm" && return 0

    section_header "Installing NVM + Node.js 22"

    if [ -d "$HOME/.nvm" ]; then
        log_info "NVM already installed"
    else
        log_info "Installing NVM..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    fi

    # Load NVM for this session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    log_info "Installing Node.js 22..."
    nvm install 22
    nvm alias default 22
    nvm use default
    log_success "NVM and Node.js 22 installed"

    mark_step_complete "install_nvm"
}

install_docker() {
    skip_if_complete "install_docker" && return 0

    section_header "Installing Docker Desktop"

    if brew list --cask docker &>/dev/null; then
        log_info "Docker Desktop already installed"
    else
        log_info "Installing Docker Desktop via Homebrew Cask..."
        brew install --cask docker
        log_success "Docker Desktop installed"
        log_info "Open Docker Desktop from Applications to complete setup"
    fi

    mark_step_complete "install_docker"
}

install_tailscale() {
    skip_if_complete "install_tailscale" && return 0

    section_header "Installing Tailscale VPN"

    if brew list --cask tailscale &>/dev/null; then
        log_info "Tailscale already installed"
    else
        log_info "Installing Tailscale..."
        brew install --cask tailscale
        log_success "Tailscale installed"
        log_info "Open Tailscale from Applications to connect"
    fi

    mark_step_complete "install_tailscale"
}

install_claude() {
    skip_if_complete "install_claude" && return 0

    section_header "Installing Claude Code CLI"

    if command -v claude &> /dev/null; then
        log_info "Claude Code already installed"
    else
        log_info "Installing Claude Code..."
        curl -fsSL https://installs.claude.ai/install.sh | sh
        log_success "Claude Code installed"
        log_info "Run 'claude auth' to authenticate"
    fi

    mark_step_complete "install_claude"
}

install_cask_apps() {
    skip_if_complete "install_cask_apps" && return 0

    section_header "Installing GUI Applications"

    install_cask_if_selected() {
        local flag="$1"
        local cask_name="$2"
        local display_name="$3"

        if [ "$flag" = "y" ]; then
            if brew list --cask "$cask_name" &>/dev/null; then
                log_info "$display_name already installed"
            else
                log_info "Installing $display_name..."
                brew install --cask "$cask_name" || log_warning "Failed to install $display_name"
            fi
        fi
    }

    install_cask_if_selected "$INSTALL_ITERM2" "iterm2" "iTerm2"
    install_cask_if_selected "$INSTALL_VSCODE" "visual-studio-code" "Visual Studio Code"
    install_cask_if_selected "$INSTALL_SUBLIME" "sublime-text" "Sublime Text"
    install_cask_if_selected "$INSTALL_DBEAVER" "dbeaver-community" "DBeaver"
    install_cask_if_selected "$INSTALL_CHROME" "google-chrome" "Google Chrome"
    install_cask_if_selected "$INSTALL_ALFRED" "alfred" "Alfred"
    install_cask_if_selected "$INSTALL_OBSIDIAN" "obsidian" "Obsidian"

    log_success "GUI applications installed"

    mark_step_complete "install_cask_apps"
}

setup_dotfiles() {
    skip_if_complete "setup_dotfiles" && return 0

    section_header "Setting Up Dotfiles"

    # Clone dotfiles if not present
    if [ ! -d "$DOTFILES_DIR" ]; then
        log_info "Cloning dotfiles repository..."
        git clone https://github.com/tanker327/dotfiles.git "$DOTFILES_DIR"
        log_success "Dotfiles cloned to $DOTFILES_DIR"
    else
        log_info "Dotfiles directory already exists at $DOTFILES_DIR"
        log_info "Pulling latest changes..."
        git -C "$DOTFILES_DIR" pull || log_warning "Failed to pull latest dotfiles"
    fi

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Backup and symlink .gitconfig
    if [ -f "$HOME/.gitconfig" ] && [ ! -L "$HOME/.gitconfig" ]; then
        log_info "Backing up existing .gitconfig..."
        mv -f "$HOME/.gitconfig" "$BACKUP_DIR/.gitconfig.$(date +%Y%m%d_%H%M%S)"
    fi
    ln -sf "$DOTFILES_DIR/git/gitconfig" "$HOME/.gitconfig"
    log_info "Symlinked .gitconfig"

    # Backup and symlink .gitignore_global
    if [ -f "$HOME/.gitignore_global" ] && [ ! -L "$HOME/.gitignore_global" ]; then
        log_info "Backing up existing .gitignore_global..."
        mv -f "$HOME/.gitignore_global" "$BACKUP_DIR/.gitignore_global.$(date +%Y%m%d_%H%M%S)"
    fi
    ln -sf "$DOTFILES_DIR/git/gitignore_global" "$HOME/.gitignore_global"
    log_info "Symlinked .gitignore_global"

    # Symlink .zshrc (after Oh My Zsh so it doesn't get overwritten)
    if [ "$INSTALL_ZSH" = "y" ]; then
        if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
            log_info "Backing up existing .zshrc..."
            mv -f "$HOME/.zshrc" "$BACKUP_DIR/.zshrc.$(date +%Y%m%d_%H%M%S)"
        fi
        ln -sf "$DOTFILES_DIR/zsh/zshrc" "$HOME/.zshrc"
        log_info "Symlinked .zshrc"
    fi

    # Symlink .p10k.zsh if it exists in dotfiles
    if [ -f "$DOTFILES_DIR/zsh/p10k.zsh" ]; then
        if [ -f "$HOME/.p10k.zsh" ] && [ ! -L "$HOME/.p10k.zsh" ]; then
            log_info "Backing up existing .p10k.zsh..."
            mv -f "$HOME/.p10k.zsh" "$BACKUP_DIR/.p10k.zsh.$(date +%Y%m%d_%H%M%S)"
        fi
        ln -sf "$DOTFILES_DIR/zsh/p10k.zsh" "$HOME/.p10k.zsh"
        log_info "Symlinked .p10k.zsh"
    fi

    log_success "Dotfiles configured"

    mark_step_complete "setup_dotfiles"
}

configure_git() {
    skip_if_complete "configure_git" && return 0

    section_header "Configuring Git"

    log_info "Setting Git user name: $GIT_USER_NAME"
    git config --global user.name "$GIT_USER_NAME"

    log_info "Setting Git email: $GIT_USER_EMAIL"
    git config --global user.email "$GIT_USER_EMAIL"

    log_success "Git configured"

    mark_step_complete "configure_git"
}

generate_ssh_key() {
    skip_if_complete "generate_ssh_key" && return 0

    section_header "SSH Key Generation"

    if [ -f "$HOME/.ssh/id_ed25519" ]; then
        log_info "SSH key already exists at ~/.ssh/id_ed25519"
    else
        log_info "Generating ED25519 SSH key..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -C "$GIT_USER_EMAIL" -f "$HOME/.ssh/id_ed25519" -N ""
        log_success "SSH key generated at ~/.ssh/id_ed25519"

        echo "" >> "$SETUP_INFO_FILE"
        echo "=== SSH PUBLIC KEY ===" >> "$SETUP_INFO_FILE"
        cat "$HOME/.ssh/id_ed25519.pub" >> "$SETUP_INFO_FILE"
        echo "======================" >> "$SETUP_INFO_FILE"
        echo "" >> "$SETUP_INFO_FILE"
    fi

    mark_step_complete "generate_ssh_key"
}

#####################################################
# Summary
#####################################################

generate_todo_content() {
    local content=""

    content+="========================================\n"
    content+="macOS Setup - Next Steps & TODO List\n"
    content+="========================================\n"
    content+="Installation completed: $(date)\n"
    content+="Machine: $(hostname)\n"
    content+="========================================\n\n"

    content+="=== INSTALLED COMPONENTS ===\n\n"
    [ "$INSTALL_HOMEBREW" = "y" ] && content+="  Done - Homebrew\n"
    [ "$INSTALL_TOOLS" = "y" ] && content+="  Done - Common CLI tools\n"
    [ "$INSTALL_ZSH" = "y" ] && content+="  Done - Zsh + Oh My Zsh + Powerlevel10k\n"
    [ "$INSTALL_UV" = "y" ] && content+="  Done - UV with Python 3.12\n"
    [ "$INSTALL_NVM" = "y" ] && content+="  Done - NVM with Node.js 22\n"
    [ "$INSTALL_DOCKER" = "y" ] && content+="  Done - Docker Desktop\n"
    [ "$INSTALL_TAILSCALE" = "y" ] && content+="  Done - Tailscale VPN\n"
    [ "$INSTALL_CLAUDE" = "y" ] && content+="  Done - Claude Code CLI\n"
    [ "$INSTALL_ITERM2" = "y" ] && content+="  Done - iTerm2\n"
    [ "$INSTALL_VSCODE" = "y" ] && content+="  Done - Visual Studio Code\n"
    [ "$INSTALL_SUBLIME" = "y" ] && content+="  Done - Sublime Text\n"
    [ "$INSTALL_DBEAVER" = "y" ] && content+="  Done - DBeaver\n"
    [ "$INSTALL_CHROME" = "y" ] && content+="  Done - Google Chrome\n"
    [ "$INSTALL_ALFRED" = "y" ] && content+="  Done - Alfred\n"
    [ "$INSTALL_OBSIDIAN" = "y" ] && content+="  Done - Obsidian\n"
    [ "$INSTALL_DOTFILES" = "y" ] && content+="  Done - Dotfiles configuration\n"
    [ "$GENERATE_SSH_KEY" = "y" ] && content+="  Done - SSH key generation\n"

    content+="\n========================================\n"
    content+="=== NEXT STEPS ===\n"
    content+="========================================\n\n"

    local step=1

    if [ "$INSTALL_ZSH" = "y" ]; then
        content+="$step. Configure Powerlevel10k prompt:\n"
        content+="   Restart your terminal - the configuration wizard will start automatically\n"
        content+="   To reconfigure later: p10k configure\n\n"
        step=$((step + 1))
    fi

    if [ "$INSTALL_DOCKER" = "y" ]; then
        content+="$step. Open Docker Desktop from Applications to complete setup\n\n"
        step=$((step + 1))
    fi

    if [ "$INSTALL_TAILSCALE" = "y" ]; then
        content+="$step. Open Tailscale from Applications and sign in\n\n"
        step=$((step + 1))
    fi

    if [ "$INSTALL_CLAUDE" = "y" ]; then
        content+="$step. Authenticate Claude Code:\n"
        content+="   claude auth\n\n"
        step=$((step + 1))
    fi

    if [ "$GENERATE_SSH_KEY" = "y" ]; then
        content+="$step. Add your SSH public key to GitHub/GitLab:\n"
        content+="   View it with: cat ~/.ssh/id_ed25519.pub\n"
        content+="   - GitHub: https://github.com/settings/keys\n"
        content+="   - GitLab: https://gitlab.com/-/profile/keys\n\n"
        step=$((step + 1))
    fi

    content+="$step. Restart your terminal to apply all changes\n\n"

    content+="========================================\n"
    content+="=== IMPORTANT FILES ===\n"
    content+="========================================\n\n"
    content+="- Setup details: ~/.mac-setup-info.txt\n"
    content+="- This TODO list: ~/after_setup_todo.txt\n"
    content+="- Dotfiles: ~/dotfiles\n"
    content+="- Zsh config: ~/.zshrc -> ~/dotfiles/zsh/zshrc\n"
    content+="- Git config: ~/.gitconfig -> ~/dotfiles/git/gitconfig\n\n"

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
    content+="========================================\n"

    echo "$content"
}

show_summary() {
    section_header "Installation Complete!"

    echo -e "${GREEN}macOS setup completed successfully${NC}"
    echo ""
    echo "Installation details saved to: $SETUP_INFO_FILE"
    echo ""

    # Generate todo content
    TODO_CONTENT=$(generate_todo_content)

    # Display to console
    echo -e "${YELLOW}$TODO_CONTENT${NC}"

    # Log summary
    echo "" >> "$SETUP_INFO_FILE"
    echo "========================================" >> "$SETUP_INFO_FILE"
    echo "Installation completed at $(date)" >> "$SETUP_INFO_FILE"
    echo "========================================" >> "$SETUP_INFO_FILE"

    # Create after_setup_todo.txt
    TODO_FILE="$HOME/after_setup_todo.txt"
    log_info "Creating after setup todo list at $TODO_FILE..."
    echo -e "$TODO_CONTENT" > "$TODO_FILE"
    chmod 644 "$TODO_FILE"
    log_success "After setup todo list created at $TODO_FILE"

    echo ""
    echo -e "${GREEN}A detailed todo list has been saved to: ${BLUE}$TODO_FILE${NC}"
    echo -e "${YELLOW}   View it anytime with: ${BLUE}cat ~/after_setup_todo.txt${NC}"

    # Clean up state file on successful completion
    log_info "Cleaning up state file..."
    rm -f "$STATE_FILE"
    log_success "Installation state cleaned up"
}

#####################################################
# Main Installation Flow
#####################################################

main() {
    check_macos
    check_not_root

    # Phase 1: Collect all inputs
    collect_user_inputs

    echo ""
    section_header "Starting Installation"
    log_info "Installation started at $(date)"

    # Phase 2: Install components
    [ "$INSTALL_HOMEBREW" = "y" ] && install_homebrew
    [ "$INSTALL_TOOLS" = "y" ] && install_common_tools
    [ "$INSTALL_ZSH" = "y" ] && install_zsh_environment
    [ "$INSTALL_UV" = "y" ] && install_uv
    [ "$INSTALL_NVM" = "y" ] && install_nvm
    [ "$INSTALL_DOCKER" = "y" ] && install_docker
    [ "$INSTALL_TAILSCALE" = "y" ] && install_tailscale
    [ "$INSTALL_CLAUDE" = "y" ] && install_claude
    install_cask_apps

    # Phase 3: Dotfiles and Git config
    [ "$INSTALL_DOTFILES" = "y" ] && setup_dotfiles
    configure_git
    [ "$GENERATE_SSH_KEY" = "y" ] && generate_ssh_key

    # Phase 4: Summary
    show_summary
}

#####################################################
# Script Entry Point
#####################################################

main "$@"
