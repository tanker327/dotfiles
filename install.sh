#!/bin/bash

#####################################################
# Dotfiles Installation Script
#####################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
CURRENT_FOLDER="$(pwd)"
BACKUP_FOLDER="$HOME/.backup"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

#####################################################
# Utility Functions
#####################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

section_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

#####################################################
# Installation Functions
#####################################################

create_backup_folder() {
    if [ ! -d "$BACKUP_FOLDER" ]; then
        log_info "Creating backup folder..."
        mkdir -p "$BACKUP_FOLDER"
        log_success "Backup folder created at $BACKUP_FOLDER"
    else
        log_info "Backup folder already exists"
    fi
}

install_oh_my_zsh() {
    section_header "Installing Oh My Zsh"

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log_info "Installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        log_success "Oh My Zsh installed"
    else
        log_info "Oh My Zsh already installed"
    fi
}

install_zsh_plugins() {
    section_header "Installing Zsh Plugins"

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
}

install_powerlevel10k() {
    section_header "Installing Powerlevel10k Theme"

    # Install Powerlevel10k
    if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
        log_info "Installing Powerlevel10k..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
        log_success "Powerlevel10k installed"
    else
        log_info "Powerlevel10k already installed"
    fi
}

setup_zsh() {
    section_header "Setting Up Zsh Configuration"

    # Backup existing zshrc
    if [ -f "$HOME/.zshrc" ]; then
        log_info "Backing up existing .zshrc..."
        mv -f "$HOME/.zshrc" "$BACKUP_FOLDER/.zshrc.$(date +%Y%m%d_%H%M%S)"
    fi

    # Create symlink for zshrc
    log_info "Creating symlink for .zshrc..."
    ln -sf "$CURRENT_FOLDER/zsh/zshrc" "$HOME/.zshrc"
    log_success "Zsh configuration linked"

    # Backup existing p10k config if it's a regular file (not a symlink)
    if [ -f "$HOME/.p10k.zsh" ] && [ ! -L "$HOME/.p10k.zsh" ]; then
        log_info "Backing up existing .p10k.zsh..."
        mv -f "$HOME/.p10k.zsh" "$BACKUP_FOLDER/.p10k.zsh.$(date +%Y%m%d_%H%M%S)"
    fi

    # Create symlink for p10k config if it exists in dotfiles
    if [ -f "$CURRENT_FOLDER/zsh/p10k.zsh" ]; then
        log_info "Creating symlink for .p10k.zsh..."
        ln -sf "$CURRENT_FOLDER/zsh/p10k.zsh" "$HOME/.p10k.zsh"
        log_success "Powerlevel10k configuration linked"
    fi
}

setup_git() {
    section_header "Setting Up Git Configuration"

    # Backup and symlink gitconfig
    if [ -f "$HOME/.gitconfig" ]; then
        log_info "Backing up existing .gitconfig..."
        mv -f "$HOME/.gitconfig" "$BACKUP_FOLDER/.gitconfig.$(date +%Y%m%d_%H%M%S)"
    fi

    log_info "Creating symlink for .gitconfig..."
    ln -sf "$CURRENT_FOLDER/git/gitconfig" "$HOME/.gitconfig"
    log_success "Git config linked"

    # Backup and symlink gitignore_global
    if [ -f "$HOME/.gitignore_global" ]; then
        log_info "Backing up existing .gitignore_global..."
        mv -f "$HOME/.gitignore_global" "$BACKUP_FOLDER/.gitignore_global.$(date +%Y%m%d_%H%M%S)"
    fi

    log_info "Creating symlink for .gitignore_global..."
    ln -sf "$CURRENT_FOLDER/git/gitignore_global" "$HOME/.gitignore_global"
    log_success "Git ignore linked"
}

#####################################################
# Main Installation Flow
#####################################################

main() {
    section_header "Dotfiles Installation"
    log_info "Starting dotfiles installation..."
    log_info "Current folder: $CURRENT_FOLDER"

    create_backup_folder
    install_oh_my_zsh
    install_zsh_plugins
    install_powerlevel10k
    setup_zsh
    setup_git

    section_header "Installation Complete!"
    echo ""
    echo -e "${GREEN}✓ Dotfiles installed successfully${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Reload your shell: source ~/.zshrc"
    if [ ! -f "$CURRENT_FOLDER/zsh/p10k.zsh" ]; then
        echo "2. Configure Powerlevel10k: p10k configure"
        echo "3. Or restart your terminal"
    else
        echo "2. Or restart your terminal"
    fi
    echo ""
    log_info "Backups saved to: $BACKUP_FOLDER"
}

main "$@"

